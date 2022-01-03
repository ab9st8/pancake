# Pancake
Pancake is a stack-oriented programming language.

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
This is not a very mature project just yet! A lot of crucial design choices with many potential ramifications are being made right now and the codebase still isn't as efficient as I'd want it to be.

## Installing and using
**Prerequisites:**
* the Nim toolchain (Nim compiler >= 1.4.0, Nimble).

To install Pancake, run

```
nimble install https://github.com/c1m5j/pancake
```

This will install the release-version Pancake interpreter. Now you can interpret Pancake source files using

```
pancake FILENAME
```

If this goes into more "stable" territory I'll also try to add this repo to the Nimble register so you can just run `nimble install pancake`.

## Design and syntax, or "How to Pancake"
Every Pancake source file consists of a number of private and public procedure definitions and a single global procedure definition. The global procedure is the entrypoint of the program; you can think of it like "main" in C/C++. Everything inside `global` is Pancake code, which consists either of stack operations, conditional clauses, variable assigments / calls or procedure calls. That is also what other procedures are made up of.

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
* string (characters enclosed by two `"`s, no newlines allowed),
* number (floating-point and integer),
* boolean (either `true` or `false`).

### I/O
For now the only input/output supported is that through the console. You can use the following keywords:
* `in` gets a single line of input from stdin, parses it to its corresponding Pancake type, and emplaces it on the local stack,
* `out` expects a single value on the stack and prints it to stdout. Concatenation of strings nor parsing values into strings is not yet implemented.

### Procedures
Pancake supports delegating tasks in a reusable way using the concept of *private and public procedures* which I came up with.

The definition of a public procedure looks like this:
```
public procedure n {
    code
}
```
where `procedure` is the name of the procedure and `n` is the number (non-negative integer) of arguments the procedure accepts. The syntax for defining a private procedure is identical, except `public` is replaced with `private`.

When a procedure is called, it pops `n` arguments from its local stack and can then access them in its code using `$x`, `x` ranging between `1` and `n`. Arguments are numbered top to bottom; or right to left:
```
($3)  ($2)  ($1)
 3     9     2   sumThree
```

The difference between public and private procedures is where they operate. When you call a public procedure, it does not create a new stack. If you reference values in a public procedure, they will be pushed to the stack of the procedure in which you called it. If you call a public procedure in `global`, it will operate on the `global` stack.

Private procedures, in contrast, will operate on their own stack when they get called. The top value from that stack, if it exists, will be pushed to the stack of the procedure in which the call occured — kind of like a `return` value.

Thus the etymological dichotomy of "public" and "private": public procedures operate "publicly", private procedures operate "privately" on their own stacks.

The reason you'd want to distinguish these two types of procedures (I think) is related to how they're supposed to work. A private procedure expects a number of arguments and it may or may not return a single value in return. A public procedure is more flexible and can operate on your stack in whatever way you choose.

The keyword `ret` can be used to abort executing a procedure (and in the case of private procedures, return the top value from the stack at that time). It is somewhat equivalent to `return` in other languages.

Another note about public procedures is; even if you're not planning on using any arguments, you can still make the argument count match however many arguments you want your procedure to *expect*. For example, a replacement for the `~` pop operator might look something like this:
```
public pop 1 {}
```

### Conditional structures
Along with variable assignment, conditional structures are the only type of Pancake code which is not deterministic in a reverse-Polish notation sense. You can't really say how many instructions an if-clause should have. You could let the theoretical `if` operator know how many instructions it should execute (or skip if the condition is false), but that is pretty uncomfortable. However I still think they're implemented in a comfy (in my opinion) manner which disguises its relative design flaws.

An if-clause begins with the `?` operator and ends at the `.` operator. The `?` operator pops a single value from its local stack and checks for its falseyness (a falsey value in Pancake is either 0 or false). If the value is falsey, execution simply jumps to the next `.` token. If the value is true, runtime proceeds. As an example, a simple stoppable `cat` program (also in "examples/cat.pancake"):

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

Pancake supports a crippled way of storing values for a longer amount of time with some kind of "variables". Assigning to them is done with the keyword `to`. `to` pops a value from the local stack and *expects an identifier* past it, the name of the variable. The name must not be the name of a procedure. For example,
```
global {
    2 to c
    c 3 + out
}
```
prints 5.

All variables are mutable. In order to change the value of a variable, simply assign to it with `to` again.

Variables are """"""function-scoped"""""". Variables are unique to their procedure and a variable called `x` in `global` is different than a variable called `x` in a private or public procedure.

That also means that you cannot call values of a parent procedure in a call. If you create a variable `a` in `global` and then call a procedure, that procedure does not have access to `a`. The planned way to implement giving access is reference literals which are only an idea for now.

## Benchmarks
*(This treats about Pancake v0.1.5)*

After I had implemented tail recursion optimisation, I decided to benchmark Pancake against Python 3.9.6 once again (the first time Python had won in Fibonacci and Pancake in factorials), only this time using tail-recursive versions of those algorithms (really just trying to exploit the fact that Python doesn't optimise that).

Tested with `hyperfine --warmup 10 "pancake benchmark.pancake" "python3 benchmark.py"` on a 2019 MacBook Pro with a 2.4 Ghz quad-core Intel i5 and 16 GB of RAM (no other apps running), results are as follows:

| | **20!** | **fib(20)**|
|-|---------|------------|
|**Pancake v0.1.5**|**2.0 ms ± 0.4 ms**|**1.9 ms ± 0.4 ms**|
|**Python v3.9.6**|34.6 ms ± 1.6 ms|34.5 ms ±   1.3 ms|
|**result**|Pancake **17.3× faster**|Pancake **17.9× faster**|

Code used for the benchmarks (these specifically) is located in the "benchmarks" directory.

## Future
<!-- Features expected in the future are
* data structures — I can't really tell if arrays have a place in this language, but at the same time it's odd to not have them,
* a way to import Pancake files into other Pancake files in order to use its procedures. That brings us to
* a standard library with common stuff that Pancake doesn't have and that could be defined using Pancake itself. Other than that, if we want stuff that can't be defined using Pancake, we also want
* foreign function interfacing with Nim — just a way to write Pancake procedures in Nim and be able to call them in Pancake code. -->
What I'm planning to work on is
* [X] _(implemented in v0.1.5)_ tail-recursive procedure optimisation for public procedures (because we can),
* [X] ("master-runtime-splitup" branch) splitting up the current runtime into a parser (to implement: optimising conditional jumps so the runtime doesn't have to check whether to skip every other instruction) and a runtime,
* [ ] implementing more complex data types in a no-nonsense way (thinking of arrays and maybe objects/tables/dictionaries/whatever you want to call them specifically),
* [ ] (1) implementing other control flow structures, such as loops and other conditional structures ("while" loops have been designed and are to be implemented),
* [ ] (related to (1)) extending and implementing the idea of *marker-based programming*, which would justify non-reverse-Polish notation constructs such as "while" loops and conditional clauses,
* [ ] allowing the runtime to generate a binary file with the all the info another runtime would need in order to run the program, basically allow redistribution of Pancake programs in compiled form,
* [ ] creating a standard library in Nim,
* [ ] allowing for identifiers to be treated as literals and be pushed to the stack, just as numbers and strings and booleans. That way we can make them procedure arguments and have procedures call other procedures. An appropriate "call" operator (most probably `'`) would have to be implemented as well,
* [ ] having a "reference" operator which would expect a single identifier and push a single *reference literal*. This is a large idea that I can't fully fit into a single bullet point, but it's interesting,
* [ ] (2) switching the procedure definition format to `fn name(a b ... -- c d ...)`, where `a` and `b` are arguments and `c` and `d` are the values being returned — by utilising this we can have 1. named parameters, 2. the stack effect of the procedure, 3. a different number of return values than just one.
* [ ] (in contradiction to (2)) switching the procedure definition format to something that is reverse-Polish notation compatible. That way we achieve a form of homoiconicity.