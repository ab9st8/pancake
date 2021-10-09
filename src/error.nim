type
    PancakeError* = ref object of CatchableError
        pos*, kind*, message*: string