from options import Option, some, none

type
    Stack*[T] = ref object
        content*: seq[T]

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