def factorial_accumulate(n, acc):
    if n == 0: return acc
    return factorial_accumulate(n - 1, acc*n)

def factorial(n):
    return factorial_accumulate(n, 1)

print(factorial(20))
