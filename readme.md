# Pancake
Pancake is the result of a month-or-two of tinkering around in Nim with an idea for a toy language I had. It's a[n almost purely!] stack-oriented interpreted programming language.

```
private factorial 1 {
    $1 1 =? 1 ret.
    $1 1 - factorial $1 *
}

global {
    5 factorial out
}
```

**What Pancake isn't:**
* serious,
* well-made,
* performant,
* bugless,
* a proper demostration of Nim's capabilities in language development,
* idiomatic Nim code.

**What Pancake is:**
* fun to play around with,
* an interesting concept that could be expanded into even more interesting territory.

## Name etymology
Because
> a Pancake stack is the best kind of stack.

*— Robert Nystrom, paraphrase*

## Installing and using
**Prerequisites:**
* the Nim toolchain (Nim compiler >= 1.4.0, Nimble).

To install Pancake, clone this repository and run
```
nimble install
```
This will install the release Pancake interpreter. Now you can interpret Pancake source files using
```
pancake FILENAME
```
I'm planning on compiling this project with the JS backend and somehow make a playground site so you don't have to install Nim just to play around with Pancake.

## Design and syntax
Every Pancake source file consists of a number of private and public procedure definitions and a single global procedure definition. The global procedure is the entrypoint of the program; you can think of it like "main" in C / C++. Everything inside `global` is Pancake code, which consists either of stack operations, conditional clauses, variable assigments or procedure calls. That is also what other procedures are made up of.

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

An if-clause begins with the `?` operator and ends at the `.` operator. The `?` operator pops a single value from its local stack and checks for its falseyness. A falsey value in Pancake is either 0 or false. If the value is false, runtime simply skips to the next `.` token. If the value is true, runtime proceeds. For an example, a simple stoppable `cat` program:

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

## Surprises!
After I cleaned up this code for the first time and built a release binary, I decided to benchmark Pancake against Python 3.7.6, just for fun. The benchmarks I ran were

* naïve calculation of 20!,
* naïve calculation of the 25th Fibonacci number.

If you have any other ideas for benchmarks both Pancake and Python could handle, shoot! I'm excited to compare Python and Pancake because...

**Pancake did not lose both benchmarks!** The results I got with
```
hyperfine --warmup 5 "python3 benchmark.py" "pancake benchmark.pancake"
```
for both benchmarks were

|             | 22!           | fib(25)        |
|-------------|---------------|----------------|
| **Pancake** | **2.1 ± 0.5 ms**  | 457.0 ± 2.8 ms |
| **Python**  | 35.2 ± 1.7 ms | **59.7 ± 2.0 ms**  |
| **result** | Pancake 16.4× faster | Python 7.7× faster|

Which is really surprising!! I never would've thought Pancake would even work as I intended it to in the beginning, and here it turns out it beats Python in a benchmark — although a puny one, if we're being frank.

Something which is interesting, to me at least, is the contrast between the two benchmarks. I wonder what makes Pancake slow down so much with Fibonacci and speed up so much with the factorial. I implemented both Fibonacci and the factorial as a public procedure in order to minimize private stack-related shenanigans in the runtime.

I put the code I used for both of the benchmarks in the "benchmarks" directory.

## Future
A known incomptenece of Pancake (aside from just the language itself) is every time a private procedure is called, Pancake c`reates a new stack. This is rather inefficient memory-wise and could be fixed, for example, by creating a new stack only for every level of procedure nestation.

Features expected in the future are
* data structures — I can't really tell if arrays have a place in this language, but at the same time it's odd to not have them,
* a way to import Pancake files into other Pancake files in order to use its procedures. That brings us to
* a standard library with common stuff that Pancake doesn't have and that could be defined using Pancake itself. Other than that, if we want stuff that can't be defined using Pancake, we also want
* foreign function interfacing with Nim — just a way to write Pancake procedures in Nim and be able to call them in Pancake code.