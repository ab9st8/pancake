# Pancake
Pancake is the result of a month-or-two of tinkering around in Nim with an idea for a toy language I had. It's a[n almost purely!] stack-oriented interpreted programming language.

```
private factorial 1 {
    1 $1 =? 1 ret.
    1 $1 - factorial $1 *
}

global {
    "Enter a number smaller than 10, and I'll print its factorial:" out
    in to input
    input 10 - neg?
        "Please enter a number smaller than 10!" out
        ret.
    "Factorial is:" out
    input factorial out
}
```

**Pancake isn't:**
* serious,
* well-made,
* performant,
* bugless,
* a proper demostration of Nim's capabilities in language development,
* idiomatic Nim code.

**Pancake is:**
* fun to play around with,
* an interesting concept that could be expanded into even more interesting territory.

## Name etymology
Because
> a Pancake stack is the best kind of stack.

*— Robert Nystrom, paraphrase*

## Installing and using
**Prerequisites:**
* the Nim toolchain (Nim compiler >= 1.4.0, Nimble).

To install Pancake, and run
```
nimble install https://github.com/c1m5j/pancake
```
This will install the release-version Pancake interpreter. Now you can interpret Pancake source files using
```
pancake FILENAME
```
I'm planning on compiling this project with the JS backend and somehow make a playground site so you don't have to install Nim just to play around with Pancake.

If this goes into more "stable" territory I'll also try to add this repo to the Nimble register so you can just run `nimble install pancake`.

## Design and syntax, or "How to Pancake"
Every Pancake source file consists of a number of private and public procedure definitions and a single global procedure definition. The global procedure is the entrypoint of the program; you can think of it like "main" in C/C++. Everything inside `global` is Pancake code, which consists either of stack operations, conditional clauses, variable assigments or procedure calls. That is also what other procedures are made up of.

### Comments
Comments span one line each, they start with a semi-colon `;`.
```
; this is a comment
; you can have two lines of comments!
; ... three even!
global {
    "Hello world!" out ; this is also a comment
}
```

### Stack operations
A value is placed on its local stack simply by being referenced in the code. You can manipulate the stack using various operators and procedures:

* `+` expects two numbers. It emplaces their sum on the stack,
* `-` expects two numbers. It emplaces their difference on the stack,
* `*` expects two numbers. It emplaces their product on the stack,
* `/` expects two numbers. It emplaces their quotient on the stack,
* `!` expects a boolean value. It emplaces its boolean negation on the stack,
* `&` expects two boolean values. It emplaces their boolean conjunction on the stack,
* `|` expects two boolean values. It emplaces their boolean alternative on the stack,
* `=` expects two values. It emplaces `true` on the stack if the values are the same with regard to type and value, and `false` otherwise.
* `dup` emplaces the topmost value on the stack again, **dup**licating it,
* `sw` **sw**aps the two topmost values on the stack,
* `rot` **rot**ates the three topmost values on the stack; the third topmost value becomes the topmost value, the second topmost value becomes the third topmost value, and the topmost value becomes the second topmost value,
* `~` pops a single value from the stack (use discouraged, not even sure if this has a place in the language).

Values in Pancake have one of three types:
* string (UTF-8 characters enclosed by two `"`s, no newlines allowed),
* number (floating-point and integer),
* boolean (either `true` or `false`).

### I/O
For now the only input/output supported is that through the console. You can use the following keywords:
* `in` gets a single line of input from stdin, parses it to its corresponding Pancake type, and emplaces it on the local stack,
* `out` expects a single value on the stack and prints it to stdout.

### Procedures
Pancake supports delegating tasks in a reusable way using the concept of *private and public procedures* which I came up with.

The syntax of the definition of a public procedure looks like this:
```
public procedure n {
    code
}
```
where `procedure` is the name of the procedure and `n` is the number of arguments the procedure accepts. The syntax for defining a private procedure is identical, except `public` is replaced with `private`.

When a procedure is called, it pops `n` arguments from its local stack and can then access them in its code using `$x`, `x` ranging between `1` and `n`. Arguments are numbered from the top to the bottom; or right to left:
```
|$3|  |$2|  |$1|
 1     2     3   sumThree
```

The difference between public and private procedures is where they operate. When you call a public procedure, it acts as if you pasted its code wherever you just called it from; sort of like a C macro, but not exactly. That is to say, if you reference values in a public procedure, they will be pushed to the stack of the procedure in which you called it. If you call a public procedure in `global`, it will operate on the `global` stack.

Private procedures, in contrast, will operate on their own stack when they get called. The top value from that stack, if it exists, will be pushed to the stack of the procedure where it was called, kind of like a `return` statement.

Thus the etymological dichotomy of "public" and "private": public procedures operate "publicly", private procedures operate "privately" on their own stacks.

The reason you'd want to distinguish these two types of procedures (I think) is related to how they're supposed to work. A private procedure expects a number of arguments and it may or may not return a single value in return. A public procedure is more flexible and can operate on your stack in whatever way you choose.

The keyword `ret` can be used to abort executing a procedure (and in the case of private procedures, return the top value from the stack at that time). It is somewhat equivalent to `return` in other languages.

Another note about public procedures is; even if you're not planning on using any arguments, you can still make the argument count match however many arguments you want your procedure to *expect*.

### Conditional structures
Along with variable assignment, conditional structures are the only type of Pancake code which is not deterministic in a reverse-Polish notation sense. That is to say, you can't really say how many instructions an if-clause should have. You could let the theoretical `if` operator know how many instructions it should execute (or skip if the condition is false), but that is like playing oracle. As I've said, conditionals in Pancake are not truly reverse-Polish notation compatible, but they're implemented in a comfy (in my opinion) manner which disguises its relative design flaws.

An if-clause begins with the `?` operator and ends at the `.` operator. The `?` operator pops a single value from its local stack and checks for its falseyness. A falsey value in Pancake is either 0 or false. If the value is false, runtime simply skips to the next `.` token. If the value is true, runtime proceeds. As an example, a simple stoppable `cat` program:

```
public cat 1 {
    in dup $1 =!? out $1 cat.
}

global {
    "stop" cat
}
```
In this case, the single argument of the `cat` procedure is the string which will stop the program. If the input is anything but that argument, we print it and make `cat` recur with its original argument.

### Variables
**Warning: this is the least developed part of the language and the least thought about. I decided to implement it on a whim and I'm not sure if it's even exactly right.**

Pancake supports a crippled way of storing values for a longer amount of time with some kind of "variables". Assigning to them is done with the keyword `to`. `to` pops a value from the local stack and *expects an identifier* past it, the name of the variable. For example,
```
global {
    2 to c
    c 3 + out
}
```
prints 5.

All variables are mutable. In order to change the value of a variable, simply assign to it with `to` again.

Variables are """"""function-scoped"""""". Variables are unique to their procedure and a variable called `name` in `global` is different than a variable called `name` in a private or public procedure.

## Benchmarks
*(This treats about Pancake v0.1.5)*

After implement tail recursion optimisation, I decided to benchmark Pancake against Python 3.9.6 once again (the first time Python had won in Fibonacci and Pancake in factorials), only this time using tail-recursive versions of those algorithms (really just trying to exploit the fact that Python doesn't optimise that).

Tested with `hyperfine --warmup 10 "pancake benchmark.pancake" "python3 benchmark.py"` on a 2019 MacBook Pro with a 2.4 Ghz quad-core Intel i5 and 16 GB of RAM (no other apps running), results are as follows:

| | **20!** | **fib(20)**|
|-|---------|------------|
|**Pancake v0.1.5**|**2.0 ms ± 0.4 ms**|**1.9 ms ± 0.4 ms**|
|**Python v3.9.6**|34.6 ms ± 1.6 ms|34.5 ms ±   1.3 ms|
|**result**|Pancake **17.3× faster**|Pancake **17.9× faster**|

Don't think that this means that Pancake is "faster" than Python in any way. Time will tell whether Pancake is even competent enough to make it into further development stages, listed below.

Code used for the benchmarks (these specifically) is located in the "benchmarks" directory.

## Future
<!-- Features expected in the future are
* data structures — I can't really tell if arrays have a place in this language, but at the same time it's odd to not have them,
* a way to import Pancake files into other Pancake files in order to use its procedures. That brings us to
* a standard library with common stuff that Pancake doesn't have and that could be defined using Pancake itself. Other than that, if we want stuff that can't be defined using Pancake, we also want
* foreign function interfacing with Nim — just a way to write Pancake procedures in Nim and be able to call them in Pancake code. -->
What I'm planning to work on is
* [X] _(implemented in v0.1.5)_ tail-recursive procedure optimisation for public procedures (because we can),
* [ ] allowing the runtime to generate a binary file with the all the info another runtime would need in order to run the program, basically allow redistribution of Pancake programs,
* [ ] making the runtime a bit of its own thing (like a language backend), and then having a lexer as an additional helper to read and parse source code, so we can have languages that compile to Pancake — with that, we'd generate JS code by itself from Pancake instead of having to compile the Nim VM source code to JS,
* [ ] implementing more complex data types in a no-nonsense way (thinking of arrays specifically),
* [ ] creating a standard library with some sort of foreign function interfacing (to allow reading files, creating servers etc.),
* [ ] allowing for identifiers to be treated as literals and be pushed to the stack, just as numbers and strings and booleans. That way we can make them procedure arguments and have procedures call other procedures. An appropriate "call" operator would have to be implemented as well. Candidates are `'`, `:`, and `,`,
* [ ] supporting named parameters in procedures as well, probably written down with `private proc(a, b, c)`. Might make numbered parameters be written down as `private proc(3)` (for 3 parameters) as well.