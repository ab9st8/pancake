from options import Option, some, none

type
    ## This is a helper type for all stack-related shenanigans
    ## throughout this project.
    Stack*[T] = ref object
        content*: seq[T] ## Content of the stack

#==================================#
# PROC DEFINITIONS ----------------#
#==================================#

## Prepares and returns a new stack with content
## of type T.
proc newStack*[T](): Stack[T]

## Checks whether Stack.content is empty.
proc empty*(self: Stack): bool

## Resets the stack, deletes all items.
proc reset*(self: Stack)

## Returns the number of items on the stack.
proc len*(self: Stack): uint

## Returns the top value of the stack encased in
## a some(). If the stack is empty, returns none().
proc topValue*[T](self: Stack[T]): Option[T]

## Pushes `value` onto the stack.
proc push*[T](self: Stack[T], value: T)

## Pops one value from the stack and returns it,
## encased in a some(). If the stack is empty, returns
## none().
proc pop*[T](self: Stack[T]): Option[T]

#==================================#
# PROC IMPLEMENTATIONS ------------#
#==================================#

proc newStack*[T](): Stack[T] =
    Stack[T](
        content: newSeq[T]()
    )

proc empty*(self: Stack): bool =
    self.content.len() == 0

proc reset*(self: Stack) = self.content.setLen(0)

proc len*(self: Stack): uint = self.content.len()

proc topValue*[T](self: Stack[T]): Option[T] =
    if self.empty():
        return none[T]()
    return some(self.content[^1])


proc push*[T](self: Stack[T], value: T) =
    self.content.add(value)

proc pop*[T](self: Stack[T]): Option[T] =
    if self.empty(): return none[T]()
    return some(self.content.pop())