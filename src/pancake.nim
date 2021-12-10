when not defined(js):
    from options import isSome, get
    from terminal import styledWrite, styleDim, resetStyle
    import argparse

    import error

when defined(js):
    import sugar
    import dom

import lexer, runtime, parser as pancakeparser

## For C backend
when isMainModule and not defined(js):
    let parser = newParser("pancake"):
        help("This is the CLI that lets you communicate with your Pancake interpreter.")
        arg("filename", help="Path to file for Pancake to interpret")
    try:
        let res = parser.parse()

        let source = open(res.filename).readAll()

#==================================#
# LEXING --------------------------#
#==================================#
        var l = newLexer(source)
        l.run()
        if l.hadError():
            raise l.error.get()

#==================================#
# PARSING -------------------------#
#==================================#        
        var p = pancakeparser.newParser(l.tokens)
        p.run()
        if p.hadError():
            raise p.error.get()

#==================================#
# RUNTIME -------------------------#
#==================================#
        var r = newRuntime(l.tokens, p.procedures)
        r.run()
        if r.hadError():
            raise r.error.get()

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

## For JavaScript backend
when isMainModule and defined(js):
    ## Runs the program, taking its source code from the left-hand-side #source div.
    proc run(button: Element) =
        let textarea = document.getElementById("source")
        let source = textarea.value
        let output = document.getElementById("output")

        button.disabled = true
        
#==================================#
# LEXING --------------------------#
#==================================#
        var l = newLexer($source)
        l.run()
        if l.hadError():
            output.value = l.output
            button.disabled = false
            return

#==================================#
# PARSING -------------------------#
#==================================#        
        var p = pancakeparser.newParser(l.tokens)
        p.run()
        if p.hadError():
            output.value = p.output
            button.disabled = false

#==================================#
# RUNTIME -------------------------#
#==================================#
        var r = newRuntime(l.tokens)
        r.run()

        output.value = r.output
        button.disabled = false

    let button = document.getElementById("run")
    button.addEventListener("mousedown", (ev: Event) => run(button))