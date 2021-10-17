type
    ## Denotes the possible types of a token.
    TokenKind* = enum
        TK_LeftBrace = 0, TK_RightBrace = 1,          ## { }
        TK_Plus = 2, TK_Minus = 3, TK_Star = 4, TK_Slash = 5, ## + - * /
        TK_Neg = 6,                               ## neg
        TK_Global = 7, TK_Public = 8, TK_Private = 9,     ## global public private
        TK_Equal = 10,                             ## =
        TK_EndIf = 11, TK_BeginIf = 12,                 ## . ?
        TK_To = 13,                                ## to
        TK_Argument = 14,                          ## $ followed by a non-negative integer
        TK_Out = 15, TK_In = 16,                        ## out in
        TK_Dup = 17, TK_Pop = 18, TK_Swap = 19, TK_Rotate = 20,   ## dup ~ sw rot
        TK_Return = 21,                            ## ret
        TK_True = 22, TK_False = 23,                    ## true false
        TK_And = 24, TK_Or = 25, TK_Not = 26                 ## & | !
        TK_Number = 27,                            ## any integer or floating point number in base 10
        TK_String = 28,                            ## utf-8 characters excluding newline enclosed with "
        TK_Identifier = 29,                        ## any characters from {a..z} | {A..Z} | {_}
        TK_EOF = 30,                               ## end of file
        TK_EOP = 31                                ## end of procedure

    ## Packages data regarding a token. A seq[Token]
    ## is the result of the process of lexing and it does not
    ## get parsed into any lower-level representation, just chopped
    ## up into procedure implementations and run from there.
    Token* = ref object
        kind*:          TokenKind
        lexeme*:        string    # The "value" of the token, what portion of the source string it corresponds to
        line*, column*: uint      # The position of the token in the file
