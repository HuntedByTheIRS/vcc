module preprocess

import backend

// The predefined macros a C library's <float.h> and <limits.h> are written in
// terms of, and the names a program asks when it wants to know what this machine
// can hold. Every body here is the one gcc 16.2.1 defines for this target, so a
// header that branches on one takes gcc's path and a program that prints one
// prints gcc's answer. It was checked by running the same program under both
// compilers and comparing all thirty-three values, and by diffing
// `-dM -E` against `gcc -std=gnu99 -dM -E -x c /dev/null`.
//
// The floating-point ones are held to the shortest decimal spelling that converts
// to gcc's value on the way this compiler reads a constant, rather than to the
// text gcc writes, because the value is what a program compares against: the
// full-width spelling gcc prints for some of them rounds differently here, and a
// macro whose value is wrong is worse than one that is missing. Where the two
// spellings are the same text, as they are for `__FLT_MAX__`, the body is gcc's.

// predefine finds one predefined macro by name, and answers nothing when the
// compiler does not predefine it at all.
fn predefine(name string) ?string {
	for definition in builtins(backend.Target{ arch: 'x86_64' }) {
		if definition.name == name {
			return definition.body
		}
	}
	return none
}

fn predefine_body(name string) string {
	return predefine(name) or { '' }
}

fn test_the_standard_limits_and_float_predefines_carry_gccs_values() {
	measured := {
		'__SCHAR_MAX__':       '0x7f'
		'__SHRT_MAX__':        '0x7fff'
		'__WCHAR_MAX__':       '0x7fffffff'
		'__WCHAR_MIN__':       '(-__WCHAR_MAX__ - 1)'
		'__WINT_MAX__':        '0xffffffffU'
		'__WINT_MIN__':        '0U'
		'__FLT_RADIX__':       '2'
		'__FLT_MANT_DIG__':    '24'
		'__FLT_DIG__':         '6'
		'__FLT_MIN_EXP__':     '(-125)'
		'__FLT_MIN_10_EXP__':  '(-37)'
		'__FLT_MAX_EXP__':     '128'
		'__FLT_MAX_10_EXP__':  '38'
		'__FLT_MAX__':         '3.40282346638528859811704183484516925e+38F'
		'__FLT_EPSILON__':     '1.19209289550781250000000000000000000e-7F'
		'__FLT_MIN__':         '1.17549435082228750796873653722224568e-38F'
		'__FLT_EVAL_METHOD__': '0'
		'__DBL_MANT_DIG__':    '53'
		'__DBL_DIG__':         '15'
		'__DBL_MIN_EXP__':     '(-1021)'
		'__DBL_MIN_10_EXP__':  '(-307)'
		'__DBL_MAX_EXP__':     '1024'
		'__DBL_MAX_10_EXP__':  '308'
		'__DBL_MAX__':         '1.79769313486231570814527423731704357e+308'
		'__DBL_EPSILON__':     '2.22044604925031308084726333618164062e-16'
		'__DBL_MIN__':         '2.2250738585072014e-308'
		'__LDBL_MANT_DIG__':   '64'
		'__LDBL_DIG__':        '18'
		'__LDBL_MIN_EXP__':    '(-16381)'
		'__LDBL_MIN_10_EXP__': '(-4931)'
		'__LDBL_MAX_EXP__':    '16384'
		'__LDBL_MAX_10_EXP__': '4932'
		// The long double values carry gcc's own spelling with the `L`
		// suffix. The reader computes the value of one exactly now, so the
		// constant is the extended number rather than a double rounded to
		// eight bytes; arithmetic on it is still refused where it is written.
		'__LDBL_MAX__':        '1.18973149535723176502126385303097021e+4932L'
		'__LDBL_EPSILON__':    '1.08420217248550443400745280086994171e-19L'
		'__LDBL_MIN__':        '3.36210314311209350626267781732175260e-4932L'
		'__DECIMAL_DIG__':     '21'
	}
	for name, body in measured {
		assert predefine_body(name) == body
	}
}

// A name that is not predefined is not answered with a body, so a test cannot
// read a value out of a macro this compiler does not define.
fn test_a_name_that_is_not_predefined_has_no_body() {
	assert predefine('__NOT_A_MACRO_THIS_COMPILER_DEFINES__') == none
}

// A use of one of these is the number, which is what a header that branches on it
// reads.
fn test_a_use_of_a_predefine_is_its_value() {
	result := preprocess('int x = __FLT_RADIX__; int y = __DECIMAL_DIG__;', 'test.c', Options{})
	assert result.diagnostics.len == 0
	mut texts := []string{}
	for tok in result.tokens {
		texts << tok.text
	}
	assert texts == ['int', 'x', '=', '2', ';', 'int', 'y', '=', '21', ';']
}
