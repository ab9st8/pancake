def fib_accumulate(acc1, acc2, n):
    if n == 0:
        return acc1
    return fib_accumulate(acc2, acc1 + acc2, n-1)

def fib(n):
    return fib_accumulate(0, 1, n)

print(fib(20))
