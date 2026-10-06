# gnu/gnu99

Cases here are compiled `-std=gnu99` and their stdout compared with the recorded
file beside them, the way `../c99/` is. They cover the GNU extensions this
compiler reads: the cleanup attribute, `_Countof` and `__alignof__`, `?:` with
its middle operand left out, the function-name strings, `__auto_type`, a range
designator, case ranges, a label's address and a computed goto, the bit,
byte-swap, overflow, object-size, constant-fold and stack-allocation builtins, a
cast to a union type, a structure with no members, `_Float128`, a vector type,
and a variadic macro that names its variable arguments.
