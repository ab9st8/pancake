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
from parser import Procedure

type
    ## The runtime environment is the set of data regarding
    ## runtime that we have currently and that could change.
    ## An environment changes globally when calling another procedure
    ## and locally inside a procedure.
    Environment = object
        procedure: Procedure                        ## The current procedure
        variables: TableRef[string, Value]          ## Variables in the current procedure scope
        stack:     Stack[Value]                     ## The local stack
        arguments: seq[Value]                       ## Arguments of the local procedure (console arguments in case of `global`)
        pc:        uint                             ## Program counter (points to the token being dealt with)

    ## Packages data regarding Pancake runtime.
    Runtime = object
        when defined(js):
            ok*:      bool                        ## whether the program is okay or if it has encountered an error
            output*:  string                      ## denotes the standard output of the program in the JS backend which we would normally print out
        else:
            error*:   Option[PancakeError]        ## Potential runtime error container
        tokens:       seq[Token]                  ## Our token list which we parse and execute
        procs:        TableRef[string, Procedure] ## Runtime procedure collection
        nestation:    uint                        ## Informs us about the level of private procedure call nestation, also the index of the current private stack in Runtime.stacks
        maxNestation: uint                        ## The highest level of private procedure call nestation we've ever reached
        token:        uint                        ## The current token pointer (during parsing)
        environment:  Environment                 ## Our runtime environment
        stacks:       seq[Stack[Value]]           ## Runtime stack collection

#==================================#
# TEMPLATES -----------------------#
#==================================#

## Used to refer to the current token during runtime.
template pcVal(): Token = self.tokens[self.environment.pc]

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

## Used inside Runtime.runProcedure() to avoid copy-paste code. Describes how a binary operator should work.
template binaryOperator(operator: typed, k: typed, val: untyped): untyped =
    let val1 = self.environment.stack.pop()
    let val2 = self.environment.stack.pop()

    if val1.isNone() or val2.isNone():
        self.constructError("Expected two operands for binary operation, got one or less", runPosition)
        return
    if val1.get().kind != k or val2.get().kind != k:
        self.constructError("Invalid types for binary operation", runPosition)
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

## Used when reporting errors during runtime to avoid copy-paste code.
template runPosition: string = &"{pcVal.line}:{pcVal.column}"

## Makes checking for errors universal across backends.
template hadError*(self: Runtime): bool =
    when defined(js): not self.ok
    else: self.error.isSome()

## Prints a value to the standard output. Universal across backends.
template print(self: Runtime, val: typed): untyped =
    when defined(js):
        self.output &= val & "\n"
    else:
        echo val


#==================================#
# PROCS ---------------------------#
#==================================#

## Prepares and returns a new Runtime instance.
proc newRuntime*(tokens: seq[Token], procs: TableRef[string, Procedure]): Runtime =
    result = Runtime(
        tokens: tokens,
        procs: procs,
        stacks: newSeq[Stack[Value]](30),
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

    result.environment = Environment(
        procedure: procs["global"],
        variables: newTable[string, Value](),
        stack: result.stacks[0],
        arguments: newSeq[Value](),
        pc: procs["global"].start
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
## is not of `kind`, false is returned.
proc expect(self: Runtime, kind: TokenKind): bool =
    if int(self.environment.pc + 1) >= self.tokens.len(): false
    else: self.tokens[self.environment.pc + 1].kind == kind


## Runs a specific procedure signature from Runtime.procs.
proc runProcedure(self: var Runtime): Option[Value] =
    while self.environment.pc < self.environment.procedure.start + self.environment.procedure.length:
        {.computedGoto.}

        case pcVal.kind
        # == argument calling ==
        of TK_Argument:
            var idx = strutils.parseUInt(pcVal.lexeme)
            if idx > self.environment.procedure.argCount or idx == 0:
                self.constructError(
                    &"Argument operator calls argument no. {idx}, but current procedure only accepts {self.environment.procedure.argCount} arguments", runPosition
                )
                return
            self.environment.stack.push(self.environment.arguments[idx-1])

        # == literals ==
        of TK_Number:         literal(pcVal.lexeme.parseFloat())
        of TK_String:         literal(pcVal.lexeme)
        of TK_True, TK_False: literal(pcVal.lexeme.parseBool())

        # == keywords / important stack procedures ==
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
                self.constructError("`in` keyword not implemented in JS backend", runPosition)
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
                
        # == math and logic operators ==
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
                self.constructError("Expected boolean value when using \"not\" operator", runPosition)
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
                self.constructError("Expected two operands for equality operation, one or less given", runPosition)
                continue
            if val1.get().kind != val2.get().kind: self.environment.stack.push(newValue(false))
            elif val1.get().valueAs[] != val2.get().valueAs[]: self.environment.stack.push(newValue(false))
            else: self.environment.stack.push(newValue(true))

        # == procedure and variable calling ==
        of TK_Identifier:
            let id = pcVal.lexeme
            if id in self.procs:
                let old = self.environment

                # These are the only two ways a procedure call can be the final action
                # in a procedure; either the next token is a right brace
                # or a `ret`.
                let optimiseTailRec = self.expect(TK_RightBrace) or self.expect(TK_Return)

                self.environment = Environment(
                    procedure: self.procs[id],
                    arguments: newSeq[Value](),
                    variables: newTable[string, Value](),
                    stack: old.stack, # public procedures keep executing on their local stack
                    pc: self.procs[id].start
                )

                # Collect arguments
                for i in countup(1, int(self.environment.procedure.argCount)):
                    let val = self.environment.stack.pop()
                    if val.isNone():
                        self.constructError(&"Invalid number of arguments provided for procedure \"{self.environment.procedure.name}\"", runPosition)
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
                        self.constructError("Private procedure recursion overflow: max number of private recursive calls allowed is 30", runPosition)
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
                self.constructError(&"Unknown identifier \"{id}\"", runPosition)
                return
        of TK_To:
            inc self.environment.pc
            let tok = pcVal
            if tok.kind != TK_Identifier:
                self.constructError(&"Expected identifier when assigning to variable, got {tok.kind}", runPosition)
                return
            if tok.lexeme notin self.environment.variables and tok.lexeme.isReservedName():
                self.constructError(&"Tried to use reserved name \"{tok.lexeme}\" for variable name", runPosition)
                return
            let val = self.environment.stack.pop()
            if val.isNone():
                self.constructError(&"Did not provide value to assign to variable \"{tok.lexeme}\"", runPosition)
                return
            self.environment.variables[tok.lexeme] = val.get()

        # == stack manipulation ==
        of TK_Pop: discard self.environment.stack.pop()
        of TK_Swap:
            let val1 = self.environment.stack.pop()
            let val2 = self.environment.stack.pop()
            if val1.isNone() or val2.isNone():
                self.constructError("Expected two operands for \"swap\" operation, got one or less", runPosition)
                return
            self.environment.stack.push(val1.get())
            self.environment.stack.push(val2.get())
        of TK_Rotate:
            let val1 = self.environment.stack.pop()
            let val2 = self.environment.stack.pop()
            let val3 = self.environment.stack.pop()
            if val1.isNone() or val2.isNone() or val3.isNone():
                self.constructError("Expected three operands for \"rotate\" operation, got two or less", runPosition)
                return
            self.environment.stack.push(val2.get())
            self.environment.stack.push(val1.get())
            self.environment.stack.push(val3.get())

        # == conditionals ==
        of TK_BeginIf:
            let val = self.environment.stack.pop()
            if val.isSome():
                # see if value is falsey. if it is, skip to corresponding end-if operator
                var shouldSkip = case val.get().kind
                of VK_Bool:
                    if not val.get().valueAs.boolean: true
                    else: false
                of VK_Number:
                    if val.get().valueAs.num == 0: true
                    else: false
                else: false

                if shouldSkip:
                    let jump = parseUInt(pcVal.lexeme)
                    self.environment.pc += jump

        of TK_EndIf: discard

        of TK_Return:
            return self.environment.stack.topValue() # simply abort executing this procedure
        
        else:
            self.constructError(&"Unexpected {pcVal.kind}", runPosition)
            return

        inc self.environment.pc # advance

    result = self.environment.stack.topValue()



## Parses and runs the whole program.
proc run*(self: var Runtime) =
    # This first while loop parses (just slices from left to right brace) stack definitions and plops
    # them into Runtime.procs. They are run afterwards (starting from global).

    if self.hadError(): return

    if self.procs["global"].length == 0:
        self.constructError("No global procedure definition given", "0:0", "parsing error") # we don't have anywhere specific to point to
        return

    discard self.runProcedure() # so long, brother