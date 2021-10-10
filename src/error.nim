## This is the error type used for anything Pancake-related.
type
    PancakeError* = ref object of CatchableError
        pos*, kind*, message*: string