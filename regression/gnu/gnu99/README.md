# gnu/gnu99

Cases here are compiled `-std=gnu99`, which is what a construct only a GNU
dialect accepts needs. The first pins the cleanup attribute: the call for an
object of an inner block runs where that block ends, and does not reach out of
the block the object belongs to.

One pins a decimal cast at the boundary of a format: the exponent a zero keeps
when it is widened, the flat form a coefficient at the end of it is stored in, the
zero a value below what the destination holds answers, and the sign a
`_Decimal128` is negated by.
