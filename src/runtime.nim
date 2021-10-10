from strutils import parseFloat, parseBool, parseUInt, endsWith
from parseutils import parseFloat, parseUInt
from hashes import hash
from os import paramCount, paramStr
from math import floor
import strformat
import tables
import options


import error
from token import Token, TokenKind, TOKEN_AS_WORD
from stack import Stack, newStack, push, pop, topValue, reset
from value import Value, ValueKind, newValue

type
    ## Packages data regarding a procedure.
    Procedure = ref object
        name: string
        content: seq[Token]
        argCount: uint
        isPrivate: bool

    ## A runtime environment is the set of data regarding
    ## runtime that we have currently and that could change.
    ## An environment changes globally when calling another procedure
    ## and locally inside a procedure.
    Environment = object
        procedure: Procedure               ## The current procedure
        variables: TableRef[string, Value] ## Variables in the current procedure scope
        stack:     Stack[Value]            ## The local stack
        arguments: seq[Value]              ## Arguments of the local procedure (console arguments in case of `global`)
        condState: ConditionalState        ## Conditional state (e.g. whether we should skip execution in the given moment)
        pc:        uint                    ## Program counter (points to the token being dealt with)


    ConditionalState = ref object
        isSkipping: bool ## Whether we should skip execution because of a false if-clause.
        ifCounter: uint  ## Helps us skip if-statements inside false if-clauses.

    ## Packages data regarding Pancake runtime.
    Runtime = ref object
        error*: Option[PancakeError]
        tokens: seq[Token]
        nestation: uint
        token: uint
        environment: Environment
        procs: TableRef[string, Procedure]
        stacks*: TableRef[string, Stack[Value]]

#==================================#
# TEMPLATES -----------------------#
#==================================#

## Used to refer to the current token during runtime.
template pcVal(): untyped = self.environment.procedure.content[self.environment.pc]

## Shortcut for constructing new Procedures.
template newProc(n: string, c: seq[Token], a: uint, p: bool): untyped = Procedure(name: n, content: c, argCount: a, isPrivate: p)

## Checks whether a given name (string) is a reserved name; that is
## whether it shouldn't be used for a new procedure or variable.
template isReservedName(name: typed): untyped =
    name == "true" or
    name == "false" or
    name in self.procs or
    name in self.environment.variables

## Used when reporting errors during parsing to avoid copy-paste code.
template sourcePosition(): untyped = &"{self.tokens[self.token].line}:{self.tokens[self.token].column}"

## Used when reporting errors during runtime to avoid copy-paste code.
template runPosition(): untyped = &"{pcVal.line}:{pcVal.column}"

## Constructs an error in the runtime with the given position, message, and error kind.
template constructError(m: untyped, p: untyped, k: untyped = "runtime error"): untyped =
    self.error = some(PancakeError(message: m, pos: p, kind: k))

## Indicates whether we're looking at the last token in the source code.
template isAtEndOfSource(self: Runtime): untyped = int(self.token + 2) == self.tokens.len() # 2 = offset + TK_EOF

## Indicates whether we're looking past the last token in the source code.
template isPastEndOfSource(self: Runtime): untyped = int(self.token) + 1 >= self.tokens.len() # 1 = TK_EOF

## Used inside Runtime.runStack() to avoid copy-paste code. Describes how a binary operator should work.
template binaryOperator(operator: typed, k: typed, val: untyped): untyped =
    let val1 = self.environment.stack.pop()
    let val2 = self.environment.stack.pop()


    if val1.isNone() or val2.isNone():
        constructError(&"Expected two operands for binary operation, got one or less", runPosition)
        return
    if val1.get().kind != k or val2.get().kind != k:
        constructError(&"Invalid types for binary operation", runPosition)
        return
    
    self.environment.stack.push(
        newValue(
            operator(val1.get().valueAs.val, val2.get().valueAs.val)
        )
    )

## Used inside Runtime.runStack() to avoid copy-paste code. Describes the addition of a literal to the local stack.
template literal(v: untyped): untyped =
    let val = newValue(v)
    self.environment.stack.push(val)



#==================================#
# PROC DEFINITIONS ----------------#
#==================================#

## Prepares and returns a new Runtime instance.
proc newRuntime*(tokens: seq[Token]): Runtime

## "Expects" a specific token kind (`kind`). If the next token
## is not of `kind`, false is returned.
proc expect(self: Runtime, kind: TokenKind): bool

## Parses a private / public procedure definition.
proc parseProcedure(self: Runtime, isPrivate: bool)

## Parses and runs the whole program.
proc run*(self: Runtime)

## Runs a specific stack signature from Runtime.procs.
proc runStack(self: Runtime): Option[Value]


#==================================#
# PROC IMPLEMENTATIONS ------------#
#==================================#

proc newRuntime*(tokens: seq[Token]): Runtime =
    result = Runtime(
        error: none[PancakeError](),
        tokens: tokens,
        stacks: newTable[string, Stack[Value]](),
        procs: newTable[string, Procedure](),
        nestation: 0,
        token: 0
    )
    result.stacks["global"] = newStack[Value]()
    result.procs["global"] = newProc("global", newSeq[Token](), uint(paramCount()), false)

    result.environment = Environment(
        procedure: result.procs["global"],
        variables: newTable[string, Value](),
        stack: result.stacks["global"],
        condState: ConditionalState(
            isSkipping: false,
            ifCounter: 0
        ),
        arguments: newSeq[Value](),
        pc: 0
    )

    # get console arguments
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


proc expect(self: Runtime, kind: TokenKind): bool =
    return if self.isAtEndOfSource() or self.isPastEndOfSource(): false
    else: self.tokens[self.token + 1].kind == kind

proc parseProcedure(self: Runtime, isPrivate: bool) =
    # first, expect the procedure's name
    if not self.expect(TK_Identifier):
        constructError(if isPrivate: "Private procedure name expected"
            else: "Public procedure name expected",
            sourcePosition
        )
        return
    inc self.token

    let name = self.tokens[self.token].lexeme
    # then check if the name is available
    if name.isReservedName():
        constructError(if isPrivate: &"Attempted to use reserved name \"{name}\" for new private procedure"
            else: &"Attempted to use reserved name \"{name}\" for new public procedure",
            sourcePosition
        )
        return

    # get the argument count of the procedure; make sure it's a non-negative integer
    var argCount: uint = 0
    if self.expect(TK_Number) and '.' notin self.tokens[self.token + 1].lexeme:
        discard parseutils.parseUInt(self.tokens[self.token + 1].lexeme, argCount)
        self.procs[name] = newProc(name, newSeq[Token](), argCount, isPrivate)
    else:
        constructError("Expected non-negative integer argument count after procedure name", sourcePosition, "parsing error")
        return

    inc self.token

    # expect the opening brace
    if not self.expect(TK_LeftBrace):
        constructError(if isPrivate: &"Left brace expected after \"{name}\" private procedure definition"
            else: &"Left brace expected after \"{name}\" public procedure definition",
        sourcePosition, "parsing error")
        return
        
    self.token = self.token + 2

    # get the procedure code up until the closing brace
    while self.tokens[self.token].kind != TK_RightBrace:
        self.procs[name].content.add(self.tokens[self.token])
        inc self.token
        if self.isPastEndOfSource():
            constructError(if isPrivate: &"Unterminated private procedure \"{name}\" implementation"
                else: &"Unterminated public procedure \"{name}\" implementation",
            sourcePosition, "parsing error")
            return
    
    # add "end-of-procedure" token
    self.procs[name].content.add(Token(kind: TK_EOP))
    inc self.token

proc run*(self: Runtime) =
    # This first while loop parses (just slices from left to right brace) stack definitions and plops
    # them into Runtime.procs. They are run afterwards (starting from global).
    while self.error.isNone():
        case self.tokens[self.token].kind
        of TK_Global:
            if self.procs["global"].content.len() != 0:
                constructError("Global stack implementation already given", sourcePosition)
                return
            if not self.expect(TK_LeftBrace):
                constructError("Left brace expected after global keyword", sourcePosition)
                return
            self.token = self.token + 2

            while self.tokens[self.token].kind != TK_RightBrace:
                self.procs["global"].content.add(self.tokens[self.token])
                inc self.token
                if self.isPastEndOfSource():
                    constructError("Unterminated global stack implementation", "0:0")
                    return
            self.procs["global"].content.add(Token(kind: TK_EOP))
            
            inc self.token # go past right brace
        
        of TK_Public:  self.parseProcedure(false)
        of TK_Private: self.parseProcedure(true)
        of TK_EOF:     break

        else:
            constructError(&"Unexpected {TOKEN_AS_WORD[self.tokens[self.token].kind]}", sourcePosition, "parsing error")
            return

    if self.procs["global"].content.len() == 0:
        constructError("No global procedure definition given", "0:0", "parsing error") # we don't have anywhere specific to point to
        return

    discard self.runStack() # so long, brother


proc runStack(self: Runtime): Option[Value] =
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
                var idx: uint

                try:
                    idx = strutils.parseUInt(pcVal.lexeme)
                except ValueError:
                    echo "whoops! you shouldn't see this, for some reason you managed to break the lexing algorithm which only accepted positive integers. here you go, have a cookie 🍪"
                    quit(1)
                
                if idx > self.environment.procedure.argCount or idx == 0:
                    constructError(
                        &"Argument operator calls argument no. {idx}, but current procedure only accepts {self.environment.procedure.argCount} arguments", runPosition
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
                    of VK_String: stdout.writeLine(val.get().valueAs.str)
                    of VK_Number:
                        if floor(val.get().valueAs.num) == val.get().valueAs.num:
                            stdout.writeLine(int(val.get().valueAs.num))
                        else:
                            stdout.writeLine(val.get().valueAs.num)
                    of VK_Bool: stdout.writeLine(val.get().valueAs.boolean)
                else: stdout.writeLine("void")
            
            of TK_In:
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
                    constructError("Expected boolean value when using \"not\" operator", runPosition)
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
                    constructError("Expected two operands for equality operation, one or less given", runPosition)
                    continue
                if val1.get().kind != val2.get().kind: self.environment.stack.push(newValue(false))
                elif val1.get().valueAs[] != val2.get().valueAs[]: self.environment.stack.push(newValue(false))
                else: self.environment.stack.push(newValue(true))

            # procedure and variable calliing
            of TK_Identifier:
                let id = pcVal.lexeme
                if id in self.procs:
                    let old = self.environment

                    self.environment = Environment(
                        procedure: self.procs[pcVal.lexeme],
                        arguments: newSeq[Value](),
                        variables: newTable[string, Value](),
                        stack: old.stack, # public procedures keep executing on their local stack
                        condState: ConditionalState(
                            isSkipping: false,
                            ifCounter: 0
                        ),
                        pc: 0
                    )

                    for i in countup(1, int(self.environment.procedure.argCount)):
                        let val = self.environment.stack.pop()
                        if val.isNone():
                            constructError(&"Invalid number of arguments provided for public procedure \"{self.environment.procedure.name}\"", runPosition)
                            return
                        self.environment.arguments.add(val.get())

                    if self.environment.procedure.isPrivate:
                        if $self.nestation in self.stacks:
                            self.stacks[$self.nestation].reset()
                        else:
                            self.stacks[$self.nestation] = newStack[Value]()
                    
                    inc self.nestation
                    let val = self.runStack()
                    dec self.nestation
                    if self.error.isSome(): return

                    if self.environment.procedure.isPrivate and val.isSome:
                        old.stack.push(val.get())

                    self.environment = old

                elif id in self.environment.variables:
                    self.environment.stack.push(self.environment.variables[id])
                
                else:
                    constructError(&"Unknown identifier \"{id}\"", runPosition)
                    return

            of TK_To:
                inc self.environment.pc
                let tok = pcVal
                if tok.kind != TK_Identifier:
                    constructError(&"Expected identifier when assigning to variable, got {TOKEN_AS_WORD[tok.kind]}", runPosition)
                    return
                if tok.lexeme.isReservedName():
                    constructError(&"Tried to use reserved name \"{tok.lexeme}\" for variable name", runPosition)
                    return
                let val = self.environment.stack.pop()
                if val.isNone():
                    constructError(&"Did not provide value to assign to variable \"{tok.lexeme}\"", runPosition)
                    return
                self.environment.variables[tok.lexeme] = val.get()

            of TK_Pop: discard self.environment.stack.pop()
            of TK_Swap:
                let val1 = self.environment.stack.pop()
                let val2 = self.environment.stack.pop()
                if val1.isNone() or val2.isNone():
                    constructError("Expected two operands for \"swap\" operation, got one or less", runPosition)
                    return
                self.environment.stack.push(val1.get())
                self.environment.stack.push(val2.get())
            of TK_Rotate:
                let val1 = self.environment.stack.pop()
                let val2 = self.environment.stack.pop()
                let val3 = self.environment.stack.pop()
                if val1.isNone() or val2.isNone() or val3.isNone():
                    constructError("Expected three operands for \"rotate\" operation, got two or less", runPosition)
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
                if val.isSome:
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
                constructError(&"Unexpected {TOKEN_AS_WORD[pcVal.kind]}", runPosition)
                return

        inc self.environment.pc # advance


    self.environment.stack.topValue()