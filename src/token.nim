from tables import toTable

type
    ## Denotes the possible types of a token.
    TokenKind* = enum
        TK_LeftBrace, TK_RightBrace,          ## { }
        TK_Plus, TK_Minus, TK_Star, TK_Slash, ## + - * /
        TK_Neg,                               ## neg
        TK_Global, TK_Public, TK_Private,     ## global public private
        TK_Equal,                             ## =
        TK_EndIf, TK_BeginIf,                 ## . ?
        TK_To,                                ## to
        TK_Argument,                          ## $ followed by a non-negative integer
        TK_Out, TK_In,                        ## out in
        TK_Dup, TK_Pop, TK_Swap, TK_Rotate,   ## dup ~ sw rot
        TK_Return,                            ## ret
        TK_True, TK_False,                    ## true false
        TK_And, TK_Or, TK_Not                 ## & | !
        TK_Number,                            ## any integer or floating point number in base 10
        TK_String,                            ## utf-8 characters excluding newline enclosed with "
        TK_Identifier,                        ## any characters from {a..z} | {A..Z} | {_}
        TK_EOF,                               ## end of file
        TK_EOP                                ## end of procedure

    ## Packages data regarding a token. A seq[Token]
    ## is the result of the process of lexing and it does not
    ## get parsed into any lower-level representation, just chopped
    ## up into procedure implementations and run from there.
    Token* = ref object
        kind*:          TokenKind
        lexeme*:        string    # The "value" of the token, what portion of the source string it corresponds to
        line*, column*: uint      # The position of the token in the file

## Used in reporting errors during runtime.
const TOKEN_AS_WORD* = {
    TK_BeginIf: "\"begin if\" operator",
    TK_Return: "\"return\" keyword",
    TK_EndIf: "\"end if\" operator",
    TK_To: "\"to\" keyword",
    TK_LeftBrace: "left brace",
    TK_RightBrace: "right brace",
    TK_Plus: "plus sign",
    TK_Minus: "minus sign",
    TK_Star: "star sign",
    TK_Slash: "slash",
    TK_Neg: "\"is negative\" operator",
    TK_Global: "\"global\" keyword",
    TK_Public: "\"public\" keyword",
    TK_Private: "\"private\" keyword",
    TK_Out: "\"out\" keyword",
    TK_In: "\"in\" keyword",
    TK_Dup: "\"dup\" keyword",
    TK_String: "string literal",
    TK_Identifier: "identifier",
    TK_Number: "number literal",
    TK_True: "\"true\" value",
    TK_False: "\"false\" value",
    TK_Argument: "argument call operator",
    TK_And: "\"and\" boolean operator",
    TK_Or: "\"or\" boolean operator",
    TK_Not: "\"not\" boolean operator",
    TK_Equal: "\"equal\" operator",
    TK_Pop: "\"pop\" operator",
    TK_Swap: "\"swap\" operator",
    TK_Rotate: "\"rotate\" operator",
}.toTable()