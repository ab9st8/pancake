type
    ## Denotes the possible types of a token.
    TokenKind* = enum
        ## { }
        TK_LeftBrace = "left brace",
        TK_RightBrace = "right brace",

        ## + - * /
        TK_Plus = "plus sign",
        TK_Minus = "minus sign",
        TK_Star = "star sign",
        TK_Slash = "slash", 

        ## neg
        TK_Neg = "\"is negative\" operator",

        ## global public private
        TK_Global = "\"global\" keyword",
        TK_Public = "\"public\" keyword",
        TK_Private = "\"private\" keyword",

        ## =
        TK_Equal = "\"equal\" operator",

        ## . ?
        TK_EndIf = "\"end if\" operator",
        TK_BeginIf = "\"begin if\" operator",

        ## to
        TK_To = "\"to\" operator",

        ## $ followed by a non-negative integer
        TK_Argument = "argument call operator",

        ## out in
        TK_Out = "\"out\" operator",
        TK_In = "\"in\" operator",

        ## dup ~ sw rot
        TK_Dup = "\"dup\" operator",
        TK_Pop = "\"pop\" operator",
        TK_Swap = "\"swap\" operator",
        TK_Rotate = "\"rotate\" operator",

        ## ret
        TK_Return = "\"return\" operator",

        ## true false
        TK_True = "\"true\" boolean literal",
        TK_False = "\"false\" boolean literal",

        ## & | !
        TK_And = "\"and\" boolean operator",
        TK_Or = "\"or\" boolean operator",
        TK_Not = "\"not\" boolean operator",

        ## any integer or floating point number in base 10
        TK_Number = "number literal",

        ## utf-8 characters excluding newline enclosed with "
        TK_String = "string literal",

        ## any characters from {a..z} | {A..Z} | {_}
        TK_Identifier = "identifier",

        TK_EOF = "end of file",                           
        TK_EOP = "end of procedure"

    ## Packages data regarding a token. A seq[Token]
    ## is the result of the process of lexing and it does not
    ## get parsed into any lower-level representation, just chopped
    ## up into procedure implementations and run from there.
    Token* = ref object
        kind*:          TokenKind
        lexeme*:        string    # The "value" of the token, what portion of the source string it corresponds to
        line*, column*: uint      # The position of the token in the file