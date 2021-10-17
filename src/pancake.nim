from options import isSome, get
import sugar
import dom
import lexer, runtime

proc run(button: Element) =
    let textarea = document.getElementById("source")
    let source = textarea.value
    let output = document.getElementById("output")

    button.disabled = true
    
    let l = newLexer($source)
    l.run()
    if l.hadError:
        output.value = l.output
        button.disabled = false
        return

    let r = newRuntime(l.tokens)
    r.run()
    # this is virtually unnecessary
    # if r.hadError:
    #     output.value = r.output
    #     button.disabled = false
    #     return

    output.value = r.output

    button.disabled = false


when isMainModule and defined(js):
    let button = document.getElementById("run")
    button.addEventListener("mousedown", (ev: Event) => run(button))