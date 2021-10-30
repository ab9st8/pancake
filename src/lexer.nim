when not defined(js):
    from options import Option, none, some, isSome
    import error
import token except TOKEN_AS_WORD
import strformat, strutils

type
    ## Packages data regarding the lexing process.
    Lexer* = ref object
        when defined(js):
            ok*:     bool                     ## whether the program is okay or if it has encountered an error
            output*: string                   ## possible error of the program, `output` instead of `error` for consistency with the runtime
        else:
            error*: Option[PancakeError]     ## Potential lexing error
        source:         string               ## The given source string
        start, current: uint                 ## Lexer.source[Lexer.start]..<Lexer.source[Lexer.current] denotes the lexeme being currently processed
        line, column:   uint                 ## Indicates where in the input the lexer is working, saved to Token.line and Token.column for every token
        tokens*:        seq[Token]           ## The resulting tokens

#==================================#
# TEMPLATES -----------------------#
#==================================#

## Indicates whether we're looking at the last character in the input.
template isAtEnd(self: Lexer): bool = int(self.current + 1) == self.source.len()

## Indicates whether we're looking past the last character in the input.
template isPastEnd(self: Lexer): bool = int(self.current) >= self.source.len()

## Fetches the current character.
template getCurrent(self: Lexer): char = self.source[self.current]

## Used when reporting errors.
template sourcePosition(): untyped = &"{self.line}:{self.column}"

## Makes checking for errors universal across backends.
template hadError*(self: Lexer): bool =
    when defined(js): not self.ok
    else:             self.error.isSome()

## Constructs an error in the lexer with the given position and message.
template constructError(self: Lexer, m: string, p: string) =
    when defined(js):
        self.output = "(lexing error, " & p & ") " & m
        self.ok = false
    else:
        self.error = some(PancakeError(message: m, pos: p, kind: "lexing error"))

## Fetches the string slice from Lexer.start to Lexer.current.
template getSlice(self: Lexer): string = self.source[self.start..<self.current]

#==================================#
# PROCS ---------------------------#
#==================================#

## Prepares and returns a new Lexer instance.
proc newLexer*(source: string): Lexer =
    result = Lexer(
        source: source.replace("\t", "    "),
        start: 0,
        current: 0,
        line: 1,
        column: 1,
        tokens: newSeq[Token](),
    )
    when defined(js):
        result.ok = true
        result.output = ""
    else:
        result.error = none[PancakeError]()


## "Warps" Lexer.start to Lexer.current and takes care of columns.
proc warp(self: Lexer) =
    self.column += self.current - self.start
    self.start = self.current


## Advances through whitespace and stops at a non-whitespace character.
proc skipWhitespace(self: Lexer) =
    var comment = false
    while not self.isPastEnd():
        case self.getCurrent()
        of ' ': discard
        of '\n', '\r':
            inc self.line
            self.column = 1
            if comment: comment = false
        of ';':
            comment = true
        else:
            if not comment: break
        inc self.current
    self.warp()


## "Chomps" on input and stops Lexer.current at a place such that
## getSlice() forms a valid lexeme.
proc chomp(self: Lexer) =
    if self.getCurrent() in Digits or
    (self.getCurrent() == '-' and
    not self.isAtEnd() and
    self.source[self.current+1] in Digits):

        if self.getCurrent() == '-': inc self.current
        # handle number
        var isFloat = false
        while not self.isPastEnd() and self.getCurrent() in Digits + {'.'}:
            if self.getCurrent() == '.' and isFloat:
                self.constructError(&"Bad number signature", sourcePosition)
                break
            elif self.getCurrent() == '.' and not isFloat:
                isFloat = true
            inc self.current

    elif self.getCurrent() == '"':
        inc self.current
        while self.getCurrent() != '"':
            if self.isPastEnd() or self.getCurrent() == '\n':
                self.constructError(&"Unterminated string", sourcePosition)
                break
            inc self.current
    
    elif self.getCurrent() in {'+', '-', '/', '*', '{', '}', '!', '=', '&', '|', '?', '.', '~'}:
        inc self.current
    elif self.getCurrent() == '$':
        inc self.current
        if self.getCurrent() notin Digits:
            self.constructError("Expected natural number after argument call operator", sourcePosition)
            return
        while not self.isPastEnd() and self.getCurrent() in Digits: inc self.current
    elif self.getCurrent() in IdentStartChars:
        while not self.isPastEnd() and self.getCurrent() in IdentStartChars: inc self.current # (we don't allow numbers in identifiers)
    else:
        self.constructError(&"Unrecognized token", sourcePosition)
        return


## Processes the input.
proc run*(self: Lexer) =
    while not self.isPastEnd():
        self.skipWhitespace()
        if self.isPastEnd(): break
        self.chomp()
        if self.hadError(): return

        let slice = self.getSlice()

        var tok = Token(
            lexeme: slice,
            line: self.line,
            column: self.column
        )

        case slice
        of "":                         break # necessary?
        of "out":                      tok.kind = TK_Out
        of "neg":                      tok.kind = TK_Neg
        of "in":                       tok.kind = TK_In
        of "dup":                      tok.kind = TK_Dup
        of "global":                   tok.kind = TK_Global
        of "public":                   tok.kind = TK_Public
        of "private":                  tok.kind = TK_Private
        of "true":                     tok.kind = TK_True
        of "false":                    tok.kind = TK_False
        of "ret":                      tok.kind = TK_Return
        of "to":                       tok.kind = TK_To
        of "sw":                       tok.kind = TK_Swap
        of "rot":                      tok.kind = TK_Rotate
        of "{":                        tok.kind = TK_LeftBrace
        of "}":                        tok.kind = TK_RightBrace
        of "+":                        tok.kind = TK_Plus
        of "-":                        tok.kind = TK_Minus
        of "*":                        tok.kind = TK_Star
        of "/":                        tok.kind = TK_Slash
        of "!":                        tok.kind = TK_Not
        of "&":                        tok.kind = TK_And
        of "|":                        tok.kind = TK_Or
        of "=":                        tok.kind = TK_Equal
        of "?":                        tok.kind = TK_BeginIf
        of ".":                        tok.kind = TK_EndIf
        of "~":                        tok.kind = TK_Pop
        else:
            if slice.startsWith("\""):
                # get rid of beginning quote
                tok.lexeme = tok.lexeme[1..^1]
                tok.kind = TK_String
                inc self.current # get past closing quote
            elif slice[0] in Digits + {'-'}:
                tok.kind = TK_Number
            elif slice.validIdentifier():
                tok.kind = TK_Identifier
            elif slice.startsWith("$"):
                # get rid of $ sign
                tok.lexeme = tok.lexeme[1..^1]
                tok.kind = TK_Argument
            else:
                self.constructError(&"Unrecognized token", sourcePosition)
                break
        self.tokens.add(tok)
        self.warp()

    self.tokens.add(Token(kind: TK_EOF)) # don't really need the other fields