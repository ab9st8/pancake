from tables import toTable

type
    TokenKind* = enum
        TK_LeftBrace, TK_RightBrace,
        TK_Plus, TK_Minus, TK_Star, TK_Slash,
        TK_Neg,
        TK_Global, TK_Public, TK_Private,
        TK_Number,
        TK_String,
        TK_Identifier,
        TK_True, TK_False,
        TK_And, TK_Or,
        TK_Not,
        TK_Equal,
        TK_BeginIf, TK_Else, TK_EndIf,
        TK_To,
        TK_Argument,
        TK_Out, TK_In,
        TK_Dup, TK_Pop, TK_Swap, TK_Rotate,
        TK_Return,
        TK_EOF,
        TK_EOP # end of procedure

    Token* = ref object
        kind*: TokenKind
        lexeme*: string
        line*, column*: uint

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