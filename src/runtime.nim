when not defined(js):
    from os import paramCount, paramStr
    import error
from strutils import parseFloat, parseBool, parseUInt
from parseutils import parseFloat, parseUInt
from math import floor
import strformat
import tables
import options

from token import Token, TokenKind
from stack import Stack, newStack, push, pop, topValue, reset
from value import Value, ValueKind, newValue

type
    ## Packages data regarding a procedure.
    Procedure = ref object
        name:      string                           ## Name of the procedure
        content:   seq[Token]                       ## The procedure code, always ends with Token(kind: TK_EOP)
        argCount:  uint                             ## Expected argument count
        isPrivate: bool                             ## Whether the procedure is private (false for global, could be true, doesn't matter)

    ## The runtime environment is the set of data regarding
    ## runtime that we have currently and that could change.
    ## An environment changes globally when calling another procedure
    ## and locally inside a procedure.
    Environment = object
        procedure: Procedure                        ## The current procedure
        variables: TableRef[string, Value]          ## Variables in the current procedure scope
        stack:     Stack[Value]                     ## The local stack
        arguments: seq[Value]                       ## Arguments of the local procedure (console arguments in case of `global`)
        condState: ConditionalState                 ## Conditional state (e.g. whether we should skip execution in the given moment)
        pc:        uint                             ## Program counter (points to the token being dealt with)


    ## Helps determine the state of the machine in conditional
    ## clause terms; whether we've entered a false if-clause and
    ## should skip to the next end-if operator.
    ConditionalState = object
        isSkipping: bool                            ## Whether we should skip execution because of a false if-clause.
        ifCounter:  uint                            ## Helps us skip if-statements inside false if-clauses (if not for this, we'd stop skipping at the first end-if operator).

    ## Packages data regarding Pancake runtime.
    Runtime = object
        when defined(js):
            ok*:      bool                        ## whether the program is okay or if it has encountered an error
            output*:  string                      ## denotes the standard output of the program in the JS backend which we would normally print out
        else:
            error*:   Option[PancakeError]        ## Potential runtime error container
        tokens:       seq[Token]                  ## Our token list which we parse and execute
        nestation:    uint                        ## Informs us about the level of private procedure call nestation, also the index of the current private stack in Runtime.stacks
        maxNestation: uint                        ## The highest level of private procedure call nestation we've ever reached
        token:        uint                        ## The current token pointer (during parsing)
        environment:  Environment                 ## Our runtime environment
        procs:        TableRef[string, Procedure] ## Runtime procedure collection
        stacks:       seq[Stack[Value]]           ## Runtime stack collection

#==================================#
# TEMPLATES -----------------------#
#==================================#

## Used to refer to the current token during runtime.
template pcVal(): Token = self.environment.procedure.content[self.environment.pc]

## Shortcut for constructing new Procedures.
template newProc(n: string, c: seq[Token], a: uint, p: bool): untyped = Procedure(name: n, content: c, argCount: a, isPrivate: p)

## Checks whether a given name (string) is a reserved name; that is
## whether it shouldn't be used for a new procedure or variable.
template isReservedName(name: typed): untyped =
    name == "true" or
    name == "false" or
    name in self.procs or
    name in self.environment.variables

## Constructs an error in the runtime with the given position, message, and error kind.
proc constructError(self: var Runtime, m: string, p: string, k: string = "runtime error") =
    when defined(js):
        self.output = "(" & k & ", " & p & ") " & m
        self.ok = false
    else:
        self.error = some(PancakeError(message: m, pos: p, kind: k))

## Indicates whether we're looking at the last token in the source code.
template isAtEndOfSource(self: Runtime): untyped = int(self.token + 2) == self.tokens.len() # 2 = offset + TK_EOF

## Indicates whether we're looking past the last token in the source code.
template isPastEndOfSource(self: Runtime): untyped = int(self.token) + 1 >= self.tokens.len() # 1 = TK_EOF

## Used inside Runtime.runProcedure() to avoid copy-paste code. Describes how a binary operator should work.
template binaryOperator(operator: typed, k: typed, val: untyped): untyped =
    let val1 = self.environment.stack.pop()
    let val2 = self.environment.stack.pop()

    if val1.isNone() or val2.isNone():
        self.constructError("Expected two operands for binary operation, got one or less", self.runPosition())
        return
    if val1.get().kind != k or val2.get().kind != k:
        self.constructError("Invalid types for binary operation", self.runPosition())
        return
    
    self.environment.stack.push(
        newValue(
            operator(val1.get().valueAs.val, val2.get().valueAs.val)
        )
    )

## Used inside Runtime.runProcedure() to avoid copy-paste code. Describes the addition of a literal to the local stack.
template literal(v: untyped): untyped =
    let val = newValue(v)
    self.environment.stack.push(val)

## Used when reporting errors during parsing to avoid copy-paste code.
template sourcePosition(self: Runtime): string = &"{self.tokens[self.token].line}:{self.tokens[self.token].column}"

## Used when reporting errors during runtime to avoid copy-paste code.
template runPosition(self: Runtime): string = &"{pcVal.line}:{pcVal.column}"

## Makes checking for errors universal across backends.
template hadError*(self: Runtime): bool =
    when defined(js): not self.ok
    else: self.error.isSome()

## Prints a value to the standard output. Universal across backends.
template print(self: Runtime, val: typed): untyped =
    when defined(js):
        self.output &= val
    else:
        echo val


#==================================#
# PROCS ---------------------------#
#==================================#

## Prepares and returns a new Runtime instance.
proc newRuntime*(tokens: seq[Token]): Runtime =
    result = Runtime(
        tokens: tokens,
        stacks: newSeq[Stack[Value]](30),
        procs: newTable[string, Procedure](),
        nestation: 0,
        maxNestation: 0,
        token: 0
    )
    when defined(js):
        result.ok = true
        result.output = ""
    else:
        result.error = none[PancakeError]()

    result.stacks[0] = newStack[Value]()

    var argCount: uint = 0
    when not defined(js):
        argCount = uint(paramCount())

    result.procs["global"] = newProc("global", newSeq[Token](), argCount, false)

    result.environment = Environment(
        procedure: result.procs["global"],
        variables: newTable[string, Value](),
        stack: result.stacks[0],
        condState: ConditionalState(
            isSkipping: false,
            ifCounter: 0
        ),
        arguments: newSeq[Value](),
        pc: 0
    )

    # get console arguments, not defined for JS backend
    when not defined(js):
        for i in countup(1, paramCount()):
            let str = paramStr(i)
            var valueAsNum: float
            var value: Value
            if parseutils.parseFloat(str, valueAsNum) != 0:
                value = newValue(valueAsNum)
            elif str == "true":
                value = newValue(true)
            elif str == "false":
                value = newValue(false)
            else:
                value = newValue(str)
            result.environment.arguments.add(value)



## "Expects" a specific token kind (`kind`). If the next token
## is not of `kind`, false is returned. Used in parsing.
proc expectParse(self: Runtime, kind: TokenKind): bool =
    return if self.isAtEndOfSource() or self.isPastEndOfSource(): false
    else: self.tokens[self.token + 1].kind == kind

## "Expects" a specific token kind (`kind`). If the next token
## is not of `kind`, false is returned. Used in runtime.
proc expectRun(self: Runtime, kind: TokenKind): bool =
    return self.environment.procedure.content[self.environment.pc + 1].kind == kind


## Parses a private / public procedure definition.
proc parseProcedure(self: var Runtime, isPrivate: bool) =
    # first, expect the procedure's name
    if not self.expectParse(TK_Identifier):
        self.constructError(if isPrivate: "Private procedure name expected"
            else: "Public procedure name expected",
            self.sourcePosition()
        )
        return
    inc self.token

    let name = self.tokens[self.token].lexeme
    # then check if the name is available
    if name.isReservedName():
        self.constructError(if isPrivate: &"Attempted to use reserved name \"{name}\" for new private procedure"
            else: &"Attempted to use reserved name \"{name}\" for new public procedure",
            self.sourcePosition()
        )
        return

    # get the argument count of the procedure; make sure it's a non-negative integer
    var argCount: uint = 0
    if self.expectParse(TK_Number) and '.' notin self.tokens[self.token + 1].lexeme:
        discard parseutils.parseUInt(self.tokens[self.token + 1].lexeme, argCount)
        self.procs[name] = newProc(name, newSeq[Token](), argCount, isPrivate)
    else:
        self.constructError("Expected non-negative integer argument count after procedure name", self.sourcePosition(), "parsing error")
        return

    inc self.token

    # expect the opening brace
    if not self.expectParse(TK_LeftBrace):
        self.constructError(if isPrivate: &"Left brace expected after \"{name}\" private procedure definition"
            else: &"Left brace expected after \"{name}\" public procedure definition",
        self.sourcePosition(), "parsing error")
        return
        
    self.token = self.token + 2

    # get the procedure code up until the closing brace
    while self.tokens[self.token].kind != TK_RightBrace:
        self.procs[name].content.add(self.tokens[self.token])
        inc self.token
        if self.isPastEndOfSource():
            self.constructError(if isPrivate: &"Unterminated private procedure \"{name}\" implementation"
                else: &"Unterminated public procedure \"{name}\" implementation",
            self.sourcePosition(), "parsing error")
            return
    
    # add "end-of-procedure" token
    self.procs[name].content.add(Token(kind: TK_EOP))
    inc self.token



## Runs a specific procedure signature from Runtime.procs.
proc runProcedure(self: var Runtime): Option[Value] =
    while pcVal.kind != TK_EOP:
        # Check for branch skipping (and stop skipping if we're after a full false if-clause)
        if self.environment.condState.isSkipping:
            if pcVal.kind == TK_BeginIf: inc self.environment.condState.ifCounter
            elif pcVal.kind == TK_EndIf:
                dec self.environment.condState.ifCounter
                if self.environment.condState.ifCounter == 0:
                    self.environment.condState.isSkipping = false
        else:

            case pcVal.kind
            # argument calling
            of TK_Argument:
                var idx = strutils.parseUInt(pcVal.lexeme)
                
                if idx > self.environment.procedure.argCount or idx == 0:
                    self.constructError(
                        &"Argument operator calls argument no. {idx}, but current procedure only accepts {self.environment.procedure.argCount} arguments", self.runPosition()
                    )
                    return
                self.environment.stack.push(self.environment.arguments[idx-1])

            # literals
            of TK_Number:         literal(pcVal.lexeme.parseFloat())
            of TK_String:         literal(pcVal.lexeme)
            of TK_True, TK_False: literal(pcVal.lexeme.parseBool())

            # keywords / important stack procedures
            of TK_Out:
                let val = self.environment.stack.pop()
                if val.isSome():
                    case val.get().kind
                    of VK_String: self.print(val.get().valueAs.str)
                    of VK_Number:
                        if floor(val.get().valueAs.num) == val.get().valueAs.num:
                            self.print($int(val.get().valueAs.num))
                        else:
                            self.print($val.get().valueAs.num)
                    of VK_Bool: self.print($val.get().valueAs.boolean)
                else: self.print("void")
            
            of TK_In:
                when defined(js):
                    self.constructError("`in` keyword not implemented in JS backend", self.runPosition())
                    return
                else:
                    let input = stdin.readLine()
                    var valueAsNum: float
                    var value: Value
                    if parseutils.parseFloat(input, valueAsNum) != 0:
                        value = newValue(valueAsNum)
                    elif input == "true":
                        value = newValue(true)
                    elif input == "false":
                        value = newValue(false)
                    else:
                        value = newValue(input)
                    self.environment.stack.push(value)


            of TK_Dup:
                let val = self.environment.stack.topValue()
                if val.isSome():
                    self.environment.stack.push(newValue(val.get()))
                    
            # operators
            of TK_Plus:  binaryOperator(`+`, VK_Number, num)
            of TK_Star:  binaryOperator(`*`, VK_Number, num)
            of TK_Minus: binaryOperator(`-`, VK_Number, num)
            of TK_Slash: binaryOperator(`/`, VK_Number, num)
            of TK_Neg:
                let val = self.environment.stack.pop()
                if val.isSome():
                    self.environment.stack.push(
                        newValue(val.get().valueAs.num < 0)
                    )
            of TK_Not:
                let val = self.environment.stack.pop()
                if val.isNone() or val.get().kind != VK_Bool:
                    self.constructError("Expected boolean value when using \"not\" operator", self.runPosition())
                    break
                var res = val.get()
                res.valueAs.boolean = not res.valueAs.boolean
                self.environment.stack.push(res)

            of TK_And: binaryOperator(`and`, VK_Bool, boolean)
            of TK_Or: binaryOperator(`or`, VK_Bool, boolean)

            of TK_Equal:
                let val1 = self.environment.stack.pop()
                let val2 = self.environment.stack.pop()
                if val1.isNone() or val2.isNone():
                    self.constructError("Expected two operands for equality operation, one or less given", self.runPosition())
                    continue
                if val1.get().kind != val2.get().kind: self.environment.stack.push(newValue(false))
                elif val1.get().valueAs[] != val2.get().valueAs[]: self.environment.stack.push(newValue(false))
                else: self.environment.stack.push(newValue(true))

            # procedure and variable calliing
            of TK_Identifier:
                let id = pcVal.lexeme
                if id in self.procs:
                    let old = self.environment

                    # These are the only two ways a procedure call can be the final action
                    # in a procedure; either the next instruction is an end-of-procedure
                    # or a `ret`.
                    let optimiseTailRec = self.expectRun(TK_EOP) or self.expectRun(TK_Return)

                    self.environment = Environment(
                        procedure: self.procs[id],
                        arguments: newSeq[Value](),
                        variables: newTable[string, Value](),
                        stack: old.stack, # public procedures keep executing on their local stack
                        condState: ConditionalState(
                            isSkipping: false,
                            ifCounter: 0
                        ),
                        pc: 0
                    )

                    # Collect arguments
                    for i in countup(1, int(self.environment.procedure.argCount)):
                        let val = self.environment.stack.pop()
                        if val.isNone():
                            self.constructError(&"Invalid number of arguments provided for procedure \"{self.environment.procedure.name}\"", self.runPosition())
                            return
                        self.environment.arguments.add(val.get())

                    
                    # Advance within nestation
                    inc self.nestation

                    # Switch stack if needed
                    if self.environment.procedure.isPrivate:

                        # If we're deeper than ever before, increase the max nestation
                        if self.nestation > self.maxNestation:
                            self.maxNestation = self.nestation
                            self.stacks[self.nestation] = newStack[Value]() # Add a new stack (we haven't been here before)
                        else:
                            # Reset the stack, don't allocate a new one (we've been here before)
                            self.stacks[self.nestation].reset()
                        
                        # Error out if we are taking up too many stacks
                        if self.nestation > 29:
                            self.constructError("Private procedure recursion overflow: max number of private recursive calls allowed is 30", self.runPosition())
                            return

                        self.environment.stack = self.stacks[self.nestation]
                    else:
                        # If this is the last call in the procedure and the procedure we're
                        # calling is public, simply start executing it from the beginning
                        # without having to recursively call Runtime.runProcedure.
                        # Saves both memory (doesn't have to allocate new internal stack frames)
                        # as well as time (doesn't have to return from each recursive Runtime.runProcedure
                        # call).
                        if optimiseTailRec:
                            dec self.nestation # go back one level, we aren't recurring in any way, just jumping back to the beginning
                            continue

                    let val = self.runProcedure()
                    dec self.nestation
                    if self.hadError(): return

                    # Better to check this way than checking whether the procedure
                    # we've just finished with was private because of tail recursion
                    # optimisation, which could trick the runtime into thinking
                    # it finished with a public procedure.
                    if self.environment.stack != old.stack and val.isSome():
                        old.stack.push(val.get())

                    self.environment = old

                elif id in self.environment.variables:
                    self.environment.stack.push(self.environment.variables[id])
                
                else:
                    self.constructError(&"Unknown identifier \"{id}\"", self.runPosition())
                    return

            of TK_To:
                inc self.environment.pc
                let tok = pcVal
                if tok.kind != TK_Identifier:
                    self.constructError(&"Expected identifier when assigning to variable, got {tok.kind}", self.runPosition())
                    return
                if tok.lexeme notin self.environment.variables and tok.lexeme.isReservedName():
                    self.constructError(&"Tried to use reserved name \"{tok.lexeme}\" for variable name", self.runPosition())
                    return
                let val = self.environment.stack.pop()
                if val.isNone():
                    self.constructError(&"Did not provide value to assign to variable \"{tok.lexeme}\"", self.runPosition())
                    return
                self.environment.variables[tok.lexeme] = val.get()

            of TK_Pop: discard self.environment.stack.pop()
            of TK_Swap:
                let val1 = self.environment.stack.pop()
                let val2 = self.environment.stack.pop()
                if val1.isNone() or val2.isNone():
                    self.constructError("Expected two operands for \"swap\" operation, got one or less", self.runPosition())
                    return
                self.environment.stack.push(val1.get())
                self.environment.stack.push(val2.get())
            of TK_Rotate:
                let val1 = self.environment.stack.pop()
                let val2 = self.environment.stack.pop()
                let val3 = self.environment.stack.pop()
                if val1.isNone() or val2.isNone() or val3.isNone():
                    self.constructError("Expected three operands for \"rotate\" operation, got two or less", self.runPosition())
                    return
                self.environment.stack.push(val2.get())
                self.environment.stack.push(val1.get())
                self.environment.stack.push(val3.get())

            # == conditionals ==
            # the runtime should have 2 states to choose from;
            # - executing,
            # - not executing.
            # what state the machine is in is determined in the very first lines of this procedure.
            
            of TK_BeginIf:
                let val = self.environment.stack.pop()
                if val.isSome():
                    # see if value is falsey. if it is, skip to corresponding end-if operator
                    case val.get().kind
                    of VK_Bool:
                        if not val.get().valueAs.boolean:
                            self.environment.condState.isSkipping = true
                            inc self.environment.condState.ifCounter
                    of VK_Number:
                        if val.get().valueAs.num == 0:
                            self.environment.condState.isSkipping = true
                            inc self.environment.condState.ifCounter
                    else: discard
            of TK_EndIf: discard

            of TK_Return:
                return self.environment.stack.topValue() # simply abort executing this procedure
            
            else:
                self.constructError(&"Unexpected {pcVal.kind}", self.runPosition())
                return

        inc self.environment.pc # advance


    self.environment.stack.topValue()



## Parses and runs the whole program.
proc run*(self: var Runtime) =
    # This first while loop parses (just slices from left to right brace) stack definitions and plops
    # them into Runtime.procs. They are run afterwards (starting from global).
    while not self.hadError():
        case self.tokens[self.token].kind
        of TK_Global:
            if self.procs["global"].content.len() != 0:
                self.constructError("Global stack implementation already given", self.sourcePosition())
                return
            if not self.expectParse(TK_LeftBrace):
                self.constructError("Left brace expected after global keyword", self.sourcePosition())
                return
            self.token = self.token + 2

            while self.tokens[self.token].kind != TK_RightBrace:
                self.procs["global"].content.add(self.tokens[self.token])
                inc self.token
                if self.isPastEndOfSource():
                    self.constructError("Unterminated global stack implementation", "0:0")
                    return
            self.procs["global"].content.add(Token(kind: TK_EOP))
            
            inc self.token # go past right brace
        
        of TK_Public:  self.parseProcedure(false)
        of TK_Private: self.parseProcedure(true)
        of TK_EOF:     break

        else:
            self.constructError(&"Unexpected {self.tokens[self.token].kind}", self.sourcePosition(), "parsing error")
            return

    if self.hadError(): return

    if self.procs["global"].content.len() == 0:
        self.constructError("No global procedure definition given", "0:0", "parsing error") # we don't have anywhere specific to point to
        return

    discard self.runProcedure() # so long, brother