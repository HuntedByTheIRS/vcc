module measured

import types

// The object representation of this target, written down so that the tests assert
// against a measurement rather than against a copy of what the code happens to
// do.
//
// Every number below was printed by gcc 16.2.1 on this machine (x86_64-linux):
//
//	gcc -std=c99 -o measure measure.c && ./measure
//	  char 1/1  signed char 1/1  unsigned char 1/1
//	  short 2/2  unsigned short 2/2
//	  int 4/4  unsigned int 4/4
//	  long 8/8  unsigned long 8/8  long long 8/8  unsigned long long 8/8
//	  _Bool 1/1  float 4/4  double 8/8  long double 16/16
//	  float _Complex 8/4  double _Complex 16/8  long double _Complex 32/16
//	  void * 8/8  char * 8/8  function pointer 8/8  enum 4/4
//
// No file the compiler is built from imports this module: it exists for the
// tests, which is where a table of measurements belongs. types/ itself answers
// these questions by asking a target description, and a description that does not
// carry an entry answers nothing.
pub fn representation() types.Representation {
	mut sizes := map[types.Kind]int{}
	mut aligns := map[types.Kind]int{}
	sizes[types.Kind.bool_] = 1
	aligns[types.Kind.bool_] = 1
	sizes[types.Kind.char_] = 1
	aligns[types.Kind.char_] = 1
	sizes[types.Kind.signed_char] = 1
	aligns[types.Kind.signed_char] = 1
	sizes[types.Kind.unsigned_char] = 1
	aligns[types.Kind.unsigned_char] = 1
	sizes[types.Kind.short] = 2
	aligns[types.Kind.short] = 2
	sizes[types.Kind.unsigned_short] = 2
	aligns[types.Kind.unsigned_short] = 2
	sizes[types.Kind.int_] = 4
	aligns[types.Kind.int_] = 4
	sizes[types.Kind.unsigned_int] = 4
	aligns[types.Kind.unsigned_int] = 4
	sizes[types.Kind.long] = 8
	aligns[types.Kind.long] = 8
	sizes[types.Kind.unsigned_long] = 8
	aligns[types.Kind.unsigned_long] = 8
	sizes[types.Kind.long_long] = 8
	aligns[types.Kind.long_long] = 8
	sizes[types.Kind.unsigned_long_long] = 8
	aligns[types.Kind.unsigned_long_long] = 8
	sizes[types.Kind.float] = 4
	aligns[types.Kind.float] = 4
	sizes[types.Kind.double] = 8
	aligns[types.Kind.double] = 8
	sizes[types.Kind.long_double] = 16
	aligns[types.Kind.long_double] = 16
	sizes[types.Kind.complex_float] = 8
	aligns[types.Kind.complex_float] = 4
	sizes[types.Kind.complex_double] = 16
	aligns[types.Kind.complex_double] = 8
	sizes[types.Kind.complex_long_double] = 32
	aligns[types.Kind.complex_long_double] = 16
	sizes[types.Kind.pointer] = 8
	aligns[types.Kind.pointer] = 8
	return types.Representation{
		sizes:  sizes
		aligns: aligns
	}
}
