from parseutils import parseFloat, parseUInt
from os import paramCount
import tables
import error
import strutils, strformat
import options


from token import Token, TokenKind

type
    ## Packages data regarding a procedure.
    Procedure* = ref object
        name*:      string                           ## Name of the procedure
        start*:     uint                             ## The index of the first instruction of the procedure in the token list
        length*:    uint                             ## How many instructions in the token list belong to the procedure
        argCount*:  uint                             ## Expected argument count
        isPrivate*: bool                             ## Whether the procedure is private (false for global, could be true, doesn't matter)
    
    Parser* = object
        when defined(js):
            ok*:     bool                ## Whether parsing has succeeded or the parser has encountered an error.
            output*: string              ## Potential parsing error.
        else:
            error*:  Option[PancakeError] ## Potential parsing error.
        tokens:      seq[Token]
        procedures*: TableRef[string, Procedure]
        current:     uint

## Shortcut for constructing new Procedures.
template newProc(n: string, s: uint, l: uint, a: uint, p: bool): untyped = Procedure(name: n, start: s, length: l, argCount: a, isPrivate: p)

## Makes checking for errors universal across backends.
template hadError*(self: Parser): bool =
    when defined(js): not self.ok
    else:             self.error.isSome()

## Constructs and returns a new Parser instance.
proc newParser*(tokens: seq[Token]): Parser =
    result = Parser(
        tokens: tokens,
        procedures: newTable[string, Procedure](),
        current: 0
    )
    when defined(js):
        result.ok = false
        result.output = ""
    else:
        result.error = none[PancakeError]()

## Used when reporting errors.
template sourcePosition(): untyped =
    &"{self.tokens[self.current].line}:{self.tokens[self.current].column}"

## Constructs an error in the parser with the given position and message.
template constructError(self: var Parser, m: string, p: string): untyped =
    when defined(js):
        self.output = "(parsing error, " & p & ") " & m
        # self.output = &"(parsing error, {p}) {m}"
        self.ok = false
    else:
        self.error = some(PancakeError(message: m, pos: p, kind: "parsing error"))

## "Expects" a specific token kind (`kind`). If the next token
## is not of `kind`, false is returned.
proc expect(self: Parser, kind: TokenKind): bool =
    if int(self.current + 1) >= self.tokens.len():
        return false
    return self.tokens[self.current+1].kind == kind

## Checks whether a given name (string) is a reserved name; that is
## whether it shouldn't be used for a new procedure.
template isReservedName(name: typed): untyped =
    name == "true" or
    name == "false" or
    name in self.procedures

## Parses a private / public procedure definition.
proc parseProcedure(self: var Parser, isPrivate: bool) =
    # first, expect the procedure's name
    if not self.expect(TK_Identifier):
        self.constructError(if isPrivate: "Private procedure name expected"
            else: "Public procedure name expected",
            sourcePosition
        )
        return
    inc self.current

    let name = self.tokens[self.current].lexeme
    # then check if the name is available
    if name.isReservedName():
        self.constructError(if isPrivate: &"Attempted to use reserved name \"{name}\" for new private procedure"
            else: &"Attempted to use reserved name \"{name}\" for new public procedure",
            sourcePosition
        )
        return

    # get the argument count of the procedure; make sure it's a non-negative integer
    var argCount: uint = 0
    if self.expect(TK_Number) and '.' notin self.tokens[self.current + 1].lexeme:
        discard parseutils.parseUInt(self.tokens[self.current + 1].lexeme, argCount)
    else:
        self.constructError("Expected non-negative integer argument count after procedure name", sourcePosition)
        return

    inc self.current

    # expect the opening brace
    if not self.expect(TK_LeftBrace):
        self.constructError(if isPrivate: &"Left brace expected after \"{name}\" private procedure definition"
            else: &"Left brace expected after \"{name}\" public procedure definition",
        sourcePosition)
        return
        
    self.current = self.current + 2

    let start = self.current

    var beginIf = newSeq[uint]()

    # get the procedure code up until the closing brace
    while self.tokens[self.current].kind != TK_RightBrace:
        inc self.current
        if self.tokens[self.current].kind == TK_EOF:
            self.constructError(if isPrivate: &"Unexpected EOF while parsing private procedure \"{name}\" implementation"
                else: &"Unexpected EOF while parsing public procedure \"{name}\" implementation",
            sourcePosition)
            return
        elif self.tokens[self.current].kind == TK_BeginIf:
            beginIf.add(self.current)
        elif self.tokens[self.current].kind == TK_EndIf:
            if beginIf.len() > 0:
                let idx = beginIf.pop()
                self.tokens[idx].lexeme = $(self.current - idx)
            else:
                self.constructError("Unexpected end-if operator", sourcePosition)
                return

    if beginIf.len() > 0:
        self.constructError("Unterminated if clause", sourcePosition)
        return

    let length = self.current - start

    inc self.current # past right brace

    self.procedures[name] = newProc(name, start, length, argCount, isPrivate)



## Splits up the token list into a table of procedures,
## optimizing conditional expressions into jumps
## on its way.
proc run*(self: var Parser) =
    while int(self.current) < self.tokens.len():
        case self.tokens[self.current].kind
        of TK_Global:
            if not self.expect(TK_LeftBrace):
                self.constructError("Left brace expected after `global` keyword", sourcePosition)
                return

            self.current += 2
            let start = self.current

            var beginIf = newSeq[uint]()

            while self.tokens[self.current].kind != TK_RightBrace:
                if self.tokens[self.current].kind == TK_EOF:
                    self.constructError("Unexpected EOF while parsing global procedure", sourcePosition)
                    return
                elif self.tokens[self.current].kind == TK_BeginIf:
                    beginIf.add(self.current)
                elif self.tokens[self.current].kind == TK_EndIf:
                    if beginIf.len() > 0:
                        let idx = beginIf.pop()
                        self.tokens[idx].lexeme = $(self.current - idx)
                    else:
                        self.constructError("Unexpected end-if operator", sourcePosition)
                        return
                inc self.current

            var argCount: uint = 0
            when not defined(js):
                argCount = uint(paramCount())

            self.procedures["global"] = newProc("global", start, self.current - start, argCount, false)

            inc self.current # past right brace

            if beginIf.len() > 0:
                self.constructError("Unterminated if clause", sourcePosition)
                return

        of TK_Private: self.parseProcedure(true)
        of TK_Public: self.parseProcedure(false)
        of TK_EOF: break

        else: discard

    if "global" notin self.procedures:
        self.constructError("Global procedure definition not found", sourcePosition)
