type
    ValueKind* = enum
        ## Denotes the possible kinds of a Pancake literal.
        VK_String,
        VK_Number,
        VK_Bool

    ValueUnion {.union.} = ref object
        ## A hack to make value-handling easier and leaner. Due
        ## to the fact that unions can only hold one value at a time,
        ## and a Pancake value can only be one type at a time as well,
        ## this is a good solution to representing values dynamically during
        ## runtime.
        ## Yes, stolen from Crafting Interpreters.
        str*: string
        num*: float
        boolean*: bool

    Value* = ref object
        ## Represents a Pancake literal during runtime.
        kind*: ValueKind
        valueAs*: ValueUnion


#==================================#
# PROC DEFINITIONS ----------------#
#==================================#

## All these return Value instances from given Nim types.
proc newValue*(value: string): Value
proc newValue*(value: float): Value
proc newValue*(value: bool): Value

## This overload is used when we want to copy a Value,
## since we cannot do `val1 = val2`, as Value is a `ref object`
## and that would just copy the address.
proc newValue*(value: Value): Value

#==================================#
# PROC IMPLEMENTATIONS ------------#
#==================================#

proc newValue*(value: string): Value =
    Value(
        kind: VK_String,
        valueAs: ValueUnion(str: value)
    )

proc newValue*(value: float): Value =
    Value(
        kind: VK_Number,
        valueAs: ValueUnion(num: value)
    )

proc newValue*(value: bool): Value =
    Value(
        kind: VK_Bool,
        valueAs: ValueUnion(boolean: value)
    )

proc newValue*(value: Value): Value =
    Value(
        kind: value.kind,
        valueAs: ValueUnion(
            str: value.valueAs.str,
            num: value.valueAs.num,
            boolean: value.valueAs.boolean
        )
    )