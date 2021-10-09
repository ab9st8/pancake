from options import isSome, get
from terminal import styledWrite, styleDim, resetStyle
import error
import argparse
import lexer, runtime


when isMainModule:
    let parser = newParser("pancake"):
        help("This is the CLI that lets you communicate with your Pancake interpreter.")
        arg("filename", help="Path to file for Pancake to interpret")
    try:
        let res = parser.parse()

        let source = open(res.filename).readAll()

#==================================#
# LEXING --------------------------#
#==================================#
        let lex = newLexer(source)
        lex.run()
        if lex.error.isSome():
            raise lex.error.get()
        
#==================================#
# RUNTIME -------------------------#
#==================================#
        let runt = newRuntime(lex.tokens, source)
        runt.run()
        if runt.error.isSome():
            raise runt.error.get()

#==================================#
# ERROR HANDLING ------------------#
#==================================#
    except PancakeError as err:
        stdout.styledWrite(styleDim, "(", err.kind, ", ", err.pos, ") ", resetStyle, err.message, "\n")
        quit(1)

    except IOError:
        echo "Error: could not read file"

    except UsageError, ShortCircuit:
        echo parser.help()
        quit(1)