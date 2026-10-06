# gnu/gnu99

Cases here are compiled `-std=gnu99`, which is what a construct only a GNU
dialect accepts needs. The first pins the cleanup attribute: the call for an
object of an inner block runs where that block ends, and does not reach out of
the block the object belongs to.
