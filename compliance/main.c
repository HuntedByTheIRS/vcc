/* ==========================================================================
 * main.c -- exhaustive C99 coverage corpus (ISO/IEC 9899:1999)
 *
 * One translation unit that exercises every C99 language construct, every
 * library added or changed by C99, the C99 translation limits, and the
 * constructs whose meaning changed between C90 and C99.  Each check bumps a
 * PASS/FAIL counter; the exit status is the number of failed checks.
 *
 * Build clean with (run from the directory holding this file, so that the
 * __FILE__ checks see the bare name):
 *     gcc   -std=c99 -pedantic-errors -Wall -Wextra -Wno-trigraphs main.c -lm
 *     clang -std=c99 -pedantic-errors -Wall -Wextra -Wno-trigraphs main.c -lm
 *
 * -Wno-trigraphs is needed because section 18 contains real trigraphs, which
 * GCC and Clang translate (and warn about) in phase 1 of translation no matter
 * where they sit in the file; the code they form is only active with
 * -DC99_TRIGRAPHS.
 *
 * For a sanitizer run add -fsanitize=address,undefined and, under ASan, pass
 * ASAN_OPTIONS=allocator_may_return_null=1: section 16 deliberately asks for an
 * impossible allocation, which ASan refuses by default instead of returning
 * null.
 *
 * Sections
 *   01 preprocessor and conditional compilation
 *   02 lexical elements: comments, digraphs, UCNs, literals, escapes
 *   03 translation limits (nesting, parameters, identifiers, long strings)
 *   04 declarations: mixed decls, for-loop decls, scopes, storage classes
 *   05 types: _Bool, long long, fixed-width, complex, qualifiers
 *   06 expressions: operators, promotions, conversions, sequencing
 *   07 control flow: if/else, switch, loops, goto, labels
 *   08 functions: prototypes, recursion, varargs, inline, restrict, VLA params
 *   09 aggregates: struct, union, enum, bitfields, flexible array members
 *   10 arrays: multidimensional, VLA, compound literals, designated init
 *   11 pointers: function pointers, pointer-to-array, restrict, offsetof
 *   12 characters and wide characters
 *   13 strings and byte arrays
 *   14 numerics: fp classification, tgmath, complex, fenv, rounding
 *   15 stdio: printf/scanf families, file positioning, formatted I/O
 *   16 general utilities: allocation, qsort/bsearch, conversions, limits
 *   17 time, locale, signal, setjmp, errno, assert
 *   18 flag-dependent material (trigraphs, brace elision, _Imaginary)
 *   19 the #line directive (deliberately last: it re-numbers the file)
 * ========================================================================== */

#ifndef C99_MAIN_C
#define C99_MAIN_C

/* assert.h has a single include, so assertions are switched on before it is
 * pulled in: any -DNDEBUG from the environment is dropped first. */
#ifdef NDEBUG
#undef NDEBUG
#endif

/* Computed include: the operand of #include is macro-expanded first. */
#define C99_HEADER_STDIO <stdio.h>
#include C99_HEADER_STDIO

#include <assert.h>
#include <complex.h>
#include <ctype.h>
#include <errno.h>
#include <fenv.h>
#include <float.h>
#include <inttypes.h>
#include <iso646.h>
#include <limits.h>
#include <locale.h>
#include <math.h>
#include <setjmp.h>
#include <signal.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <tgmath.h>   /* must follow <math.h> and <complex.h> */
#include <time.h>
#include <wchar.h>
#include <wctype.h>

/* C99 6.10.3.2: an implementation claiming C99 defines __STDC_VERSION__. */
#if !defined(__STDC_VERSION__) || __STDC_VERSION__ < 199901L
#error "main.c requires a C99 implementation (build with -std=c99)"
#endif

#ifdef C99_TEST_SELF_INCLUDE
/* Re-entering this file through __FILE__: the include guard above stops the
 * recursion.  Off by default because it needs the compiler to run in the
 * directory that holds this file. */
#include __FILE__
#endif

/* ==========================================================================
 * 00 harness
 * ========================================================================== */

static int g_checks;
static int g_pass;
static int g_fail;
static int g_section_checks;

#define CHECK(...)                                                            \
    do {                                                                      \
        ++g_checks;                                                           \
        ++g_section_checks;                                                   \
        if (__VA_ARGS__) {                                                    \
            ++g_pass;                                                         \
        } else {                                                              \
            ++g_fail;                                                         \
            printf("    FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__); \
        }                                                                     \
    } while (0)

static void sec_begin(const char *title)
{
    if (g_section_checks != 0) {
        printf("    (%d checks)\n", g_section_checks);
    }
    g_section_checks = 0;
    printf("[%s]\n", title);
}

/* Floating-point comparison helpers (defined with the numerics section). */
static double c99_nearly(double a, double b);
static long double c99_nearlyl(long double a, long double b);

/* ==========================================================================
 * 01 preprocessor and conditional compilation
 * ========================================================================== */

/* Object-like, function-like, and variadic macros. */
#define C99_OBJ_MACRO 1999L
#define C99_FN_MACRO(a, b) ((a) * 1000 + (b))
#define C99_SUM3(a, b, c) ((a) + (b) + (c))
#define C99_STRINGIZE(x) #x
#define C99_EXPAND_AND_STRINGIZE(x) C99_STRINGIZE(x)
#define C99_PASTE(a, b) a##b
#define C99_PASTE_EXPAND(a, b) C99_PASTE(a, b)
#define C99_SHOW_ALL(...) #__VA_ARGS__
#define C99_NARGS(_1, _2, _3, _4, _5, N, ...) N
/* C99 6.10.3p4: a variadic macro must be invoked with at least one argument
 * for "...", so the trailing 0 keeps the counted tail non-empty. */
#define C99_COUNT(...) C99_NARGS(__VA_ARGS__, 5, 4, 3, 2, 1, 0)
#define C99_DECLARE(n) int C99_PASTE_EXPAND(c99_slot_, n) = (n)

/* Multi-line macro: line splicing inside the replacement list. */
#define C99_MULTILINE_ADD(a, b) \
    ((a) +                    \
     (b))

/* Digraphs: %: is #, %:%: is ##, <% %> <: :> are braces and brackets. */
%:define C99_DIGRAPH_DEFINED 1
%:define C99_DIGRAPH_PASTE(a, b) a %:%: b
%:define C99_DECLARE_DIGRAPH(n) int C99_DIGRAPH_PASTE(dg_var_, n) = (n) * 2

/* _Pragma: C99 6.10.9, the operator form of #pragma.  The three STDC pragmas
 * (FP_CONTRACT, FENV_ACCESS, CX_LIMITED_RANGE) are the only standard ones;
 * Clang implements them, GCC 16 still ignores all three with a warning, so
 * they are only emitted where they are understood.  Define C99_STDC_PRAGMAS
 * to force them anywhere. */
#if defined(__clang__) || defined(C99_STDC_PRAGMAS)
_Pragma("STDC FP_CONTRACT OFF")
_Pragma("STDC CX_LIMITED_RANGE ON")
#pragma STDC FENV_ACCESS ON
#endif

/* #undef and re-#define. */
#define C99_TEMP_MACRO 1
#undef C99_TEMP_MACRO

#if defined(__STDC_HOSTED__)
#define C99_HOSTED_KNOWN 1
#else
#error "__STDC_HOSTED__ must be defined"
#endif

#if defined(C99_TEMP_MACRO)
#error "C99_TEMP_MACRO should have been #undef'd"
#elif !defined(C99_TEMP_MACRO)
#define C99_TEMP_MACRO_IS_GONE 1
#else
#error "unreachable"
#endif

#if !defined(C99_NEVER_DEFINED_AT_ALL)
#if defined(C99_OBJ_MACRO) && (C99_OBJ_MACRO + 1 == 2000) && !defined(__cplusplus)
#define C99_NESTED_CONDITION 1
#endif
#endif

#if 0
#error "this #error sits in a false branch and must never fire"
#endif

#if (1 ? 2 : 3) != 2 || (0x10 >> 2) != 4 || ('a' == 97) != 1
#error "preprocessor constant-expression arithmetic is broken"
#endif

C99_DECLARE(7);
C99_DECLARE_DIGRAPH(3);

static const char *func_name_probe(void)
{
    return __func__;
}

static int sec_01_preprocessor(void)
{
    int failures = g_fail;

    sec_begin("01 preprocessor and conditional compilation");

    CHECK(C99_OBJ_MACRO == 1999L);
    CHECK(C99_FN_MACRO(1, 2) == 1002);
    CHECK(C99_SUM3(1, 2, 3) == 6);
    CHECK(C99_MULTILINE_ADD(20, 22) == 42);

    /* # does not macro-expand its operand; the two-step form does. */
    CHECK(strcmp(C99_STRINGIZE(C99_OBJ_MACRO), "C99_OBJ_MACRO") == 0);
    CHECK(strcmp(C99_EXPAND_AND_STRINGIZE(C99_OBJ_MACRO), "1999L") == 0);

    /* ## builds new identifiers. */
    CHECK(c99_slot_7 == 7);
    CHECK(dg_var_3 == 6);
    CHECK(C99_DIGRAPH_DEFINED == 1);

    /* __VA_ARGS__ and #__VA_ARGS__. */
    CHECK(strcmp(C99_SHOW_ALL(1, 2, 3), "1, 2, 3") == 0);
    CHECK(strcmp(C99_SHOW_ALL(only_one), "only_one") == 0);
    CHECK(C99_COUNT(9) == 1);
    CHECK(C99_COUNT(9, 8, 7, 6) == 4);

    CHECK(C99_HOSTED_KNOWN == 1);
    CHECK(C99_TEMP_MACRO_IS_GONE == 1);
    CHECK(C99_NESTED_CONDITION == 1);

    /* Predefined macros. */
    CHECK(__STDC_VERSION__ >= 199901L);
    CHECK(__STDC__ == 1);
    CHECK(strcmp(__FILE__, "main.c") == 0);
    CHECK(__LINE__ > 0);
    CHECK(strlen(__DATE__) >= 11);
    CHECK(strlen(__TIME__) >= 8);
    CHECK(strcmp(func_name_probe(), "func_name_probe") == 0);

    return g_fail - failures;
}

/* ==========================================================================
 * 02 lexical elements
 * ========================================================================== */

/* Every escape sequence, in a string literal and as character constants. */
static const char c99_all_escapes[] = "\a\b\f\n\r\t\v\\\'\"\?";
static const char c99_hex_escapes[] = "\x41\x42\103";

/* Universal character names; the compiler must translate these into the
 * execution character set, which for every mainstream toolchain is UTF-8. */
static const char c99_ucn_string[] = "\u00E9\u00E8\U0001F600";

/* Literals of every C99 form and suffix. */
static const long long c99_ll_max = 9223372036854775807LL;
static const unsigned long long c99_ull_max = 18446744073709551615ULL;
static const long double c99_hex_float = 0x1.8p+3L;  /* 12.0 */
static const double c99_hex_float2 = 0x.8p1;         /* 1.0 */
static const float c99_float_suffix = 3.5f;
static const double c99_double_forms[] = {1e10, 1E-10, 1., .5, 1.5e+3};

static int sec_02_lexical(void)
{
    int failures = g_fail;
    int comment_probe = 1; /* trailing line comment */
    int a = 1 + /* block comment inside an expression */
            1;

    sec_begin("02 lexical elements");

    CHECK(comment_probe == 1);
    CHECK(a == 2);

    CHECK(strlen(c99_all_escapes) == 11);
    CHECK(strcmp(c99_hex_escapes, "ABC") == 0);
    CHECK(strcmp(c99_ucn_string, "\u00E9\u00E8\U0001F600") == 0);
    CHECK(strlen(c99_ucn_string) == 8); /* 2 + 2 + 4 UTF-8 bytes */
    CHECK('\0' == 0 && '\n' == 10 && '\t' == 9 && '\v' == 11);
    CHECK('\x41' == 65 && '\101' == 65 && '\?' == '?' && '\'' == 39);
    CHECK(c99_hex_escapes[0] == 0x41 && c99_hex_escapes[2] == 0103);

    CHECK(c99_ll_max == LLONG_MAX);
    CHECK(c99_ull_max == ULLONG_MAX);
    CHECK(c99_hex_float == 12.0L);
    CHECK(c99_hex_float2 == 1.0);
    CHECK(0x1p-2 == 0.25);
    CHECK(c99_float_suffix == 3.5f);
    CHECK(c99_double_forms[0] == 1e10);
    CHECK(c99_double_forms[1] == 1E-10);
    CHECK(c99_double_forms[2] == 1.0);
    CHECK(c99_double_forms[3] == 0.5);
    CHECK(c99_double_forms[4] == 1500.0);
    CHECK(017 == 15 && 0x1F == 31 && 2147483647 == INT_MAX);

    CHECK(sizeof(char) == 1);
    CHECK((unsigned char)200 == 200);
    CHECK((signed char)-1 == -1);

    /* Whitespace forms are equivalent: tab and newline inside an expression. */
    CHECK(1	+
          1 == 2);

    return g_fail - failures;
}

/* ==========================================================================
 * 03 translation limits (C99 5.2.4.1)
 *
 * The standard guarantees these minimums; a conforming implementation must
 * swallow every construct below without diagnostics.
 * ========================================================================== */

/* 4095 macro identifiers simultaneously defined in one translation unit. */
#define C99_LIMIT_MACRO_0000 0
#define C99_LIMIT_MACRO_0001 1
#define C99_LIMIT_MACRO_0002 2
#define C99_LIMIT_MACRO_0003 3
#define C99_LIMIT_MACRO_0004 4
#define C99_LIMIT_MACRO_0005 5
#define C99_LIMIT_MACRO_0006 6
#define C99_LIMIT_MACRO_0007 7
#define C99_LIMIT_MACRO_0008 8
#define C99_LIMIT_MACRO_0009 9
#define C99_LIMIT_MACRO_0010 10
#define C99_LIMIT_MACRO_0011 11
#define C99_LIMIT_MACRO_0012 12
#define C99_LIMIT_MACRO_0013 13
#define C99_LIMIT_MACRO_0014 14
#define C99_LIMIT_MACRO_0015 15
#define C99_LIMIT_MACRO_0016 16
#define C99_LIMIT_MACRO_0017 17
#define C99_LIMIT_MACRO_0018 18
#define C99_LIMIT_MACRO_0019 19
#define C99_LIMIT_MACRO_0020 20
#define C99_LIMIT_MACRO_0021 21
#define C99_LIMIT_MACRO_0022 22
#define C99_LIMIT_MACRO_0023 23
#define C99_LIMIT_MACRO_0024 24
#define C99_LIMIT_MACRO_0025 25
#define C99_LIMIT_MACRO_0026 26
#define C99_LIMIT_MACRO_0027 27
#define C99_LIMIT_MACRO_0028 28
#define C99_LIMIT_MACRO_0029 29
#define C99_LIMIT_MACRO_0030 30
#define C99_LIMIT_MACRO_0031 31
#define C99_LIMIT_MACRO_0032 32
#define C99_LIMIT_MACRO_0033 33
#define C99_LIMIT_MACRO_0034 34
#define C99_LIMIT_MACRO_0035 35
#define C99_LIMIT_MACRO_0036 36
#define C99_LIMIT_MACRO_0037 37
#define C99_LIMIT_MACRO_0038 38
#define C99_LIMIT_MACRO_0039 39
#define C99_LIMIT_MACRO_0040 40
#define C99_LIMIT_MACRO_0041 41
#define C99_LIMIT_MACRO_0042 42
#define C99_LIMIT_MACRO_0043 43
#define C99_LIMIT_MACRO_0044 44
#define C99_LIMIT_MACRO_0045 45
#define C99_LIMIT_MACRO_0046 46
#define C99_LIMIT_MACRO_0047 47
#define C99_LIMIT_MACRO_0048 48
#define C99_LIMIT_MACRO_0049 49
#define C99_LIMIT_MACRO_0050 50
#define C99_LIMIT_MACRO_0051 51
#define C99_LIMIT_MACRO_0052 52
#define C99_LIMIT_MACRO_0053 53
#define C99_LIMIT_MACRO_0054 54
#define C99_LIMIT_MACRO_0055 55
#define C99_LIMIT_MACRO_0056 56
#define C99_LIMIT_MACRO_0057 57
#define C99_LIMIT_MACRO_0058 58
#define C99_LIMIT_MACRO_0059 59
#define C99_LIMIT_MACRO_0060 60
#define C99_LIMIT_MACRO_0061 61
#define C99_LIMIT_MACRO_0062 62
#define C99_LIMIT_MACRO_0063 63
#define C99_LIMIT_MACRO_0064 64
#define C99_LIMIT_MACRO_0065 65
#define C99_LIMIT_MACRO_0066 66
#define C99_LIMIT_MACRO_0067 67
#define C99_LIMIT_MACRO_0068 68
#define C99_LIMIT_MACRO_0069 69
#define C99_LIMIT_MACRO_0070 70
#define C99_LIMIT_MACRO_0071 71
#define C99_LIMIT_MACRO_0072 72
#define C99_LIMIT_MACRO_0073 73
#define C99_LIMIT_MACRO_0074 74
#define C99_LIMIT_MACRO_0075 75
#define C99_LIMIT_MACRO_0076 76
#define C99_LIMIT_MACRO_0077 77
#define C99_LIMIT_MACRO_0078 78
#define C99_LIMIT_MACRO_0079 79
#define C99_LIMIT_MACRO_0080 80
#define C99_LIMIT_MACRO_0081 81
#define C99_LIMIT_MACRO_0082 82
#define C99_LIMIT_MACRO_0083 83
#define C99_LIMIT_MACRO_0084 84
#define C99_LIMIT_MACRO_0085 85
#define C99_LIMIT_MACRO_0086 86
#define C99_LIMIT_MACRO_0087 87
#define C99_LIMIT_MACRO_0088 88
#define C99_LIMIT_MACRO_0089 89
#define C99_LIMIT_MACRO_0090 90
#define C99_LIMIT_MACRO_0091 91
#define C99_LIMIT_MACRO_0092 92
#define C99_LIMIT_MACRO_0093 93
#define C99_LIMIT_MACRO_0094 94
#define C99_LIMIT_MACRO_0095 95
#define C99_LIMIT_MACRO_0096 96
#define C99_LIMIT_MACRO_0097 97
#define C99_LIMIT_MACRO_0098 98
#define C99_LIMIT_MACRO_0099 99
#define C99_LIMIT_MACRO_0100 100
#define C99_LIMIT_MACRO_0101 101
#define C99_LIMIT_MACRO_0102 102
#define C99_LIMIT_MACRO_0103 103
#define C99_LIMIT_MACRO_0104 104
#define C99_LIMIT_MACRO_0105 105
#define C99_LIMIT_MACRO_0106 106
#define C99_LIMIT_MACRO_0107 107
#define C99_LIMIT_MACRO_0108 108
#define C99_LIMIT_MACRO_0109 109
#define C99_LIMIT_MACRO_0110 110
#define C99_LIMIT_MACRO_0111 111
#define C99_LIMIT_MACRO_0112 112
#define C99_LIMIT_MACRO_0113 113
#define C99_LIMIT_MACRO_0114 114
#define C99_LIMIT_MACRO_0115 115
#define C99_LIMIT_MACRO_0116 116
#define C99_LIMIT_MACRO_0117 117
#define C99_LIMIT_MACRO_0118 118
#define C99_LIMIT_MACRO_0119 119
#define C99_LIMIT_MACRO_0120 120
#define C99_LIMIT_MACRO_0121 121
#define C99_LIMIT_MACRO_0122 122
#define C99_LIMIT_MACRO_0123 123
#define C99_LIMIT_MACRO_0124 124
#define C99_LIMIT_MACRO_0125 125
#define C99_LIMIT_MACRO_0126 126
#define C99_LIMIT_MACRO_0127 127
#define C99_LIMIT_MACRO_0128 128
#define C99_LIMIT_MACRO_0129 129
#define C99_LIMIT_MACRO_0130 130
#define C99_LIMIT_MACRO_0131 131
#define C99_LIMIT_MACRO_0132 132
#define C99_LIMIT_MACRO_0133 133
#define C99_LIMIT_MACRO_0134 134
#define C99_LIMIT_MACRO_0135 135
#define C99_LIMIT_MACRO_0136 136
#define C99_LIMIT_MACRO_0137 137
#define C99_LIMIT_MACRO_0138 138
#define C99_LIMIT_MACRO_0139 139
#define C99_LIMIT_MACRO_0140 140
#define C99_LIMIT_MACRO_0141 141
#define C99_LIMIT_MACRO_0142 142
#define C99_LIMIT_MACRO_0143 143
#define C99_LIMIT_MACRO_0144 144
#define C99_LIMIT_MACRO_0145 145
#define C99_LIMIT_MACRO_0146 146
#define C99_LIMIT_MACRO_0147 147
#define C99_LIMIT_MACRO_0148 148
#define C99_LIMIT_MACRO_0149 149
#define C99_LIMIT_MACRO_0150 150
#define C99_LIMIT_MACRO_0151 151
#define C99_LIMIT_MACRO_0152 152
#define C99_LIMIT_MACRO_0153 153
#define C99_LIMIT_MACRO_0154 154
#define C99_LIMIT_MACRO_0155 155
#define C99_LIMIT_MACRO_0156 156
#define C99_LIMIT_MACRO_0157 157
#define C99_LIMIT_MACRO_0158 158
#define C99_LIMIT_MACRO_0159 159
#define C99_LIMIT_MACRO_0160 160
#define C99_LIMIT_MACRO_0161 161
#define C99_LIMIT_MACRO_0162 162
#define C99_LIMIT_MACRO_0163 163
#define C99_LIMIT_MACRO_0164 164
#define C99_LIMIT_MACRO_0165 165
#define C99_LIMIT_MACRO_0166 166
#define C99_LIMIT_MACRO_0167 167
#define C99_LIMIT_MACRO_0168 168
#define C99_LIMIT_MACRO_0169 169
#define C99_LIMIT_MACRO_0170 170
#define C99_LIMIT_MACRO_0171 171
#define C99_LIMIT_MACRO_0172 172
#define C99_LIMIT_MACRO_0173 173
#define C99_LIMIT_MACRO_0174 174
#define C99_LIMIT_MACRO_0175 175
#define C99_LIMIT_MACRO_0176 176
#define C99_LIMIT_MACRO_0177 177
#define C99_LIMIT_MACRO_0178 178
#define C99_LIMIT_MACRO_0179 179
#define C99_LIMIT_MACRO_0180 180
#define C99_LIMIT_MACRO_0181 181
#define C99_LIMIT_MACRO_0182 182
#define C99_LIMIT_MACRO_0183 183
#define C99_LIMIT_MACRO_0184 184
#define C99_LIMIT_MACRO_0185 185
#define C99_LIMIT_MACRO_0186 186
#define C99_LIMIT_MACRO_0187 187
#define C99_LIMIT_MACRO_0188 188
#define C99_LIMIT_MACRO_0189 189
#define C99_LIMIT_MACRO_0190 190
#define C99_LIMIT_MACRO_0191 191
#define C99_LIMIT_MACRO_0192 192
#define C99_LIMIT_MACRO_0193 193
#define C99_LIMIT_MACRO_0194 194
#define C99_LIMIT_MACRO_0195 195
#define C99_LIMIT_MACRO_0196 196
#define C99_LIMIT_MACRO_0197 197
#define C99_LIMIT_MACRO_0198 198
#define C99_LIMIT_MACRO_0199 199
#define C99_LIMIT_MACRO_0200 200
#define C99_LIMIT_MACRO_0201 201
#define C99_LIMIT_MACRO_0202 202
#define C99_LIMIT_MACRO_0203 203
#define C99_LIMIT_MACRO_0204 204
#define C99_LIMIT_MACRO_0205 205
#define C99_LIMIT_MACRO_0206 206
#define C99_LIMIT_MACRO_0207 207
#define C99_LIMIT_MACRO_0208 208
#define C99_LIMIT_MACRO_0209 209
#define C99_LIMIT_MACRO_0210 210
#define C99_LIMIT_MACRO_0211 211
#define C99_LIMIT_MACRO_0212 212
#define C99_LIMIT_MACRO_0213 213
#define C99_LIMIT_MACRO_0214 214
#define C99_LIMIT_MACRO_0215 215
#define C99_LIMIT_MACRO_0216 216
#define C99_LIMIT_MACRO_0217 217
#define C99_LIMIT_MACRO_0218 218
#define C99_LIMIT_MACRO_0219 219
#define C99_LIMIT_MACRO_0220 220
#define C99_LIMIT_MACRO_0221 221
#define C99_LIMIT_MACRO_0222 222
#define C99_LIMIT_MACRO_0223 223
#define C99_LIMIT_MACRO_0224 224
#define C99_LIMIT_MACRO_0225 225
#define C99_LIMIT_MACRO_0226 226
#define C99_LIMIT_MACRO_0227 227
#define C99_LIMIT_MACRO_0228 228
#define C99_LIMIT_MACRO_0229 229
#define C99_LIMIT_MACRO_0230 230
#define C99_LIMIT_MACRO_0231 231
#define C99_LIMIT_MACRO_0232 232
#define C99_LIMIT_MACRO_0233 233
#define C99_LIMIT_MACRO_0234 234
#define C99_LIMIT_MACRO_0235 235
#define C99_LIMIT_MACRO_0236 236
#define C99_LIMIT_MACRO_0237 237
#define C99_LIMIT_MACRO_0238 238
#define C99_LIMIT_MACRO_0239 239
#define C99_LIMIT_MACRO_0240 240
#define C99_LIMIT_MACRO_0241 241
#define C99_LIMIT_MACRO_0242 242
#define C99_LIMIT_MACRO_0243 243
#define C99_LIMIT_MACRO_0244 244
#define C99_LIMIT_MACRO_0245 245
#define C99_LIMIT_MACRO_0246 246
#define C99_LIMIT_MACRO_0247 247
#define C99_LIMIT_MACRO_0248 248
#define C99_LIMIT_MACRO_0249 249
#define C99_LIMIT_MACRO_0250 250
#define C99_LIMIT_MACRO_0251 251
#define C99_LIMIT_MACRO_0252 252
#define C99_LIMIT_MACRO_0253 253
#define C99_LIMIT_MACRO_0254 254
#define C99_LIMIT_MACRO_0255 255
#define C99_LIMIT_MACRO_0256 256
#define C99_LIMIT_MACRO_0257 257
#define C99_LIMIT_MACRO_0258 258
#define C99_LIMIT_MACRO_0259 259
#define C99_LIMIT_MACRO_0260 260
#define C99_LIMIT_MACRO_0261 261
#define C99_LIMIT_MACRO_0262 262
#define C99_LIMIT_MACRO_0263 263
#define C99_LIMIT_MACRO_0264 264
#define C99_LIMIT_MACRO_0265 265
#define C99_LIMIT_MACRO_0266 266
#define C99_LIMIT_MACRO_0267 267
#define C99_LIMIT_MACRO_0268 268
#define C99_LIMIT_MACRO_0269 269
#define C99_LIMIT_MACRO_0270 270
#define C99_LIMIT_MACRO_0271 271
#define C99_LIMIT_MACRO_0272 272
#define C99_LIMIT_MACRO_0273 273
#define C99_LIMIT_MACRO_0274 274
#define C99_LIMIT_MACRO_0275 275
#define C99_LIMIT_MACRO_0276 276
#define C99_LIMIT_MACRO_0277 277
#define C99_LIMIT_MACRO_0278 278
#define C99_LIMIT_MACRO_0279 279
#define C99_LIMIT_MACRO_0280 280
#define C99_LIMIT_MACRO_0281 281
#define C99_LIMIT_MACRO_0282 282
#define C99_LIMIT_MACRO_0283 283
#define C99_LIMIT_MACRO_0284 284
#define C99_LIMIT_MACRO_0285 285
#define C99_LIMIT_MACRO_0286 286
#define C99_LIMIT_MACRO_0287 287
#define C99_LIMIT_MACRO_0288 288
#define C99_LIMIT_MACRO_0289 289
#define C99_LIMIT_MACRO_0290 290
#define C99_LIMIT_MACRO_0291 291
#define C99_LIMIT_MACRO_0292 292
#define C99_LIMIT_MACRO_0293 293
#define C99_LIMIT_MACRO_0294 294
#define C99_LIMIT_MACRO_0295 295
#define C99_LIMIT_MACRO_0296 296
#define C99_LIMIT_MACRO_0297 297
#define C99_LIMIT_MACRO_0298 298
#define C99_LIMIT_MACRO_0299 299
#define C99_LIMIT_MACRO_0300 300
#define C99_LIMIT_MACRO_0301 301
#define C99_LIMIT_MACRO_0302 302
#define C99_LIMIT_MACRO_0303 303
#define C99_LIMIT_MACRO_0304 304
#define C99_LIMIT_MACRO_0305 305
#define C99_LIMIT_MACRO_0306 306
#define C99_LIMIT_MACRO_0307 307
#define C99_LIMIT_MACRO_0308 308
#define C99_LIMIT_MACRO_0309 309
#define C99_LIMIT_MACRO_0310 310
#define C99_LIMIT_MACRO_0311 311
#define C99_LIMIT_MACRO_0312 312
#define C99_LIMIT_MACRO_0313 313
#define C99_LIMIT_MACRO_0314 314
#define C99_LIMIT_MACRO_0315 315
#define C99_LIMIT_MACRO_0316 316
#define C99_LIMIT_MACRO_0317 317
#define C99_LIMIT_MACRO_0318 318
#define C99_LIMIT_MACRO_0319 319
#define C99_LIMIT_MACRO_0320 320
#define C99_LIMIT_MACRO_0321 321
#define C99_LIMIT_MACRO_0322 322
#define C99_LIMIT_MACRO_0323 323
#define C99_LIMIT_MACRO_0324 324
#define C99_LIMIT_MACRO_0325 325
#define C99_LIMIT_MACRO_0326 326
#define C99_LIMIT_MACRO_0327 327
#define C99_LIMIT_MACRO_0328 328
#define C99_LIMIT_MACRO_0329 329
#define C99_LIMIT_MACRO_0330 330
#define C99_LIMIT_MACRO_0331 331
#define C99_LIMIT_MACRO_0332 332
#define C99_LIMIT_MACRO_0333 333
#define C99_LIMIT_MACRO_0334 334
#define C99_LIMIT_MACRO_0335 335
#define C99_LIMIT_MACRO_0336 336
#define C99_LIMIT_MACRO_0337 337
#define C99_LIMIT_MACRO_0338 338
#define C99_LIMIT_MACRO_0339 339
#define C99_LIMIT_MACRO_0340 340
#define C99_LIMIT_MACRO_0341 341
#define C99_LIMIT_MACRO_0342 342
#define C99_LIMIT_MACRO_0343 343
#define C99_LIMIT_MACRO_0344 344
#define C99_LIMIT_MACRO_0345 345
#define C99_LIMIT_MACRO_0346 346
#define C99_LIMIT_MACRO_0347 347
#define C99_LIMIT_MACRO_0348 348
#define C99_LIMIT_MACRO_0349 349
#define C99_LIMIT_MACRO_0350 350
#define C99_LIMIT_MACRO_0351 351
#define C99_LIMIT_MACRO_0352 352
#define C99_LIMIT_MACRO_0353 353
#define C99_LIMIT_MACRO_0354 354
#define C99_LIMIT_MACRO_0355 355
#define C99_LIMIT_MACRO_0356 356
#define C99_LIMIT_MACRO_0357 357
#define C99_LIMIT_MACRO_0358 358
#define C99_LIMIT_MACRO_0359 359
#define C99_LIMIT_MACRO_0360 360
#define C99_LIMIT_MACRO_0361 361
#define C99_LIMIT_MACRO_0362 362
#define C99_LIMIT_MACRO_0363 363
#define C99_LIMIT_MACRO_0364 364
#define C99_LIMIT_MACRO_0365 365
#define C99_LIMIT_MACRO_0366 366
#define C99_LIMIT_MACRO_0367 367
#define C99_LIMIT_MACRO_0368 368
#define C99_LIMIT_MACRO_0369 369
#define C99_LIMIT_MACRO_0370 370
#define C99_LIMIT_MACRO_0371 371
#define C99_LIMIT_MACRO_0372 372
#define C99_LIMIT_MACRO_0373 373
#define C99_LIMIT_MACRO_0374 374
#define C99_LIMIT_MACRO_0375 375
#define C99_LIMIT_MACRO_0376 376
#define C99_LIMIT_MACRO_0377 377
#define C99_LIMIT_MACRO_0378 378
#define C99_LIMIT_MACRO_0379 379
#define C99_LIMIT_MACRO_0380 380
#define C99_LIMIT_MACRO_0381 381
#define C99_LIMIT_MACRO_0382 382
#define C99_LIMIT_MACRO_0383 383
#define C99_LIMIT_MACRO_0384 384
#define C99_LIMIT_MACRO_0385 385
#define C99_LIMIT_MACRO_0386 386
#define C99_LIMIT_MACRO_0387 387
#define C99_LIMIT_MACRO_0388 388
#define C99_LIMIT_MACRO_0389 389
#define C99_LIMIT_MACRO_0390 390
#define C99_LIMIT_MACRO_0391 391
#define C99_LIMIT_MACRO_0392 392
#define C99_LIMIT_MACRO_0393 393
#define C99_LIMIT_MACRO_0394 394
#define C99_LIMIT_MACRO_0395 395
#define C99_LIMIT_MACRO_0396 396
#define C99_LIMIT_MACRO_0397 397
#define C99_LIMIT_MACRO_0398 398
#define C99_LIMIT_MACRO_0399 399
#define C99_LIMIT_MACRO_0400 400
#define C99_LIMIT_MACRO_0401 401
#define C99_LIMIT_MACRO_0402 402
#define C99_LIMIT_MACRO_0403 403
#define C99_LIMIT_MACRO_0404 404
#define C99_LIMIT_MACRO_0405 405
#define C99_LIMIT_MACRO_0406 406
#define C99_LIMIT_MACRO_0407 407
#define C99_LIMIT_MACRO_0408 408
#define C99_LIMIT_MACRO_0409 409
#define C99_LIMIT_MACRO_0410 410
#define C99_LIMIT_MACRO_0411 411
#define C99_LIMIT_MACRO_0412 412
#define C99_LIMIT_MACRO_0413 413
#define C99_LIMIT_MACRO_0414 414
#define C99_LIMIT_MACRO_0415 415
#define C99_LIMIT_MACRO_0416 416
#define C99_LIMIT_MACRO_0417 417
#define C99_LIMIT_MACRO_0418 418
#define C99_LIMIT_MACRO_0419 419
#define C99_LIMIT_MACRO_0420 420
#define C99_LIMIT_MACRO_0421 421
#define C99_LIMIT_MACRO_0422 422
#define C99_LIMIT_MACRO_0423 423
#define C99_LIMIT_MACRO_0424 424
#define C99_LIMIT_MACRO_0425 425
#define C99_LIMIT_MACRO_0426 426
#define C99_LIMIT_MACRO_0427 427
#define C99_LIMIT_MACRO_0428 428
#define C99_LIMIT_MACRO_0429 429
#define C99_LIMIT_MACRO_0430 430
#define C99_LIMIT_MACRO_0431 431
#define C99_LIMIT_MACRO_0432 432
#define C99_LIMIT_MACRO_0433 433
#define C99_LIMIT_MACRO_0434 434
#define C99_LIMIT_MACRO_0435 435
#define C99_LIMIT_MACRO_0436 436
#define C99_LIMIT_MACRO_0437 437
#define C99_LIMIT_MACRO_0438 438
#define C99_LIMIT_MACRO_0439 439
#define C99_LIMIT_MACRO_0440 440
#define C99_LIMIT_MACRO_0441 441
#define C99_LIMIT_MACRO_0442 442
#define C99_LIMIT_MACRO_0443 443
#define C99_LIMIT_MACRO_0444 444
#define C99_LIMIT_MACRO_0445 445
#define C99_LIMIT_MACRO_0446 446
#define C99_LIMIT_MACRO_0447 447
#define C99_LIMIT_MACRO_0448 448
#define C99_LIMIT_MACRO_0449 449
#define C99_LIMIT_MACRO_0450 450
#define C99_LIMIT_MACRO_0451 451
#define C99_LIMIT_MACRO_0452 452
#define C99_LIMIT_MACRO_0453 453
#define C99_LIMIT_MACRO_0454 454
#define C99_LIMIT_MACRO_0455 455
#define C99_LIMIT_MACRO_0456 456
#define C99_LIMIT_MACRO_0457 457
#define C99_LIMIT_MACRO_0458 458
#define C99_LIMIT_MACRO_0459 459
#define C99_LIMIT_MACRO_0460 460
#define C99_LIMIT_MACRO_0461 461
#define C99_LIMIT_MACRO_0462 462
#define C99_LIMIT_MACRO_0463 463
#define C99_LIMIT_MACRO_0464 464
#define C99_LIMIT_MACRO_0465 465
#define C99_LIMIT_MACRO_0466 466
#define C99_LIMIT_MACRO_0467 467
#define C99_LIMIT_MACRO_0468 468
#define C99_LIMIT_MACRO_0469 469
#define C99_LIMIT_MACRO_0470 470
#define C99_LIMIT_MACRO_0471 471
#define C99_LIMIT_MACRO_0472 472
#define C99_LIMIT_MACRO_0473 473
#define C99_LIMIT_MACRO_0474 474
#define C99_LIMIT_MACRO_0475 475
#define C99_LIMIT_MACRO_0476 476
#define C99_LIMIT_MACRO_0477 477
#define C99_LIMIT_MACRO_0478 478
#define C99_LIMIT_MACRO_0479 479
#define C99_LIMIT_MACRO_0480 480
#define C99_LIMIT_MACRO_0481 481
#define C99_LIMIT_MACRO_0482 482
#define C99_LIMIT_MACRO_0483 483
#define C99_LIMIT_MACRO_0484 484
#define C99_LIMIT_MACRO_0485 485
#define C99_LIMIT_MACRO_0486 486
#define C99_LIMIT_MACRO_0487 487
#define C99_LIMIT_MACRO_0488 488
#define C99_LIMIT_MACRO_0489 489
#define C99_LIMIT_MACRO_0490 490
#define C99_LIMIT_MACRO_0491 491
#define C99_LIMIT_MACRO_0492 492
#define C99_LIMIT_MACRO_0493 493
#define C99_LIMIT_MACRO_0494 494
#define C99_LIMIT_MACRO_0495 495
#define C99_LIMIT_MACRO_0496 496
#define C99_LIMIT_MACRO_0497 497
#define C99_LIMIT_MACRO_0498 498
#define C99_LIMIT_MACRO_0499 499
#define C99_LIMIT_MACRO_0500 500
#define C99_LIMIT_MACRO_0501 501
#define C99_LIMIT_MACRO_0502 502
#define C99_LIMIT_MACRO_0503 503
#define C99_LIMIT_MACRO_0504 504
#define C99_LIMIT_MACRO_0505 505
#define C99_LIMIT_MACRO_0506 506
#define C99_LIMIT_MACRO_0507 507
#define C99_LIMIT_MACRO_0508 508
#define C99_LIMIT_MACRO_0509 509
#define C99_LIMIT_MACRO_0510 510
#define C99_LIMIT_MACRO_0511 511
#define C99_LIMIT_MACRO_0512 512
#define C99_LIMIT_MACRO_0513 513
#define C99_LIMIT_MACRO_0514 514
#define C99_LIMIT_MACRO_0515 515
#define C99_LIMIT_MACRO_0516 516
#define C99_LIMIT_MACRO_0517 517
#define C99_LIMIT_MACRO_0518 518
#define C99_LIMIT_MACRO_0519 519
#define C99_LIMIT_MACRO_0520 520
#define C99_LIMIT_MACRO_0521 521
#define C99_LIMIT_MACRO_0522 522
#define C99_LIMIT_MACRO_0523 523
#define C99_LIMIT_MACRO_0524 524
#define C99_LIMIT_MACRO_0525 525
#define C99_LIMIT_MACRO_0526 526
#define C99_LIMIT_MACRO_0527 527
#define C99_LIMIT_MACRO_0528 528
#define C99_LIMIT_MACRO_0529 529
#define C99_LIMIT_MACRO_0530 530
#define C99_LIMIT_MACRO_0531 531
#define C99_LIMIT_MACRO_0532 532
#define C99_LIMIT_MACRO_0533 533
#define C99_LIMIT_MACRO_0534 534
#define C99_LIMIT_MACRO_0535 535
#define C99_LIMIT_MACRO_0536 536
#define C99_LIMIT_MACRO_0537 537
#define C99_LIMIT_MACRO_0538 538
#define C99_LIMIT_MACRO_0539 539
#define C99_LIMIT_MACRO_0540 540
#define C99_LIMIT_MACRO_0541 541
#define C99_LIMIT_MACRO_0542 542
#define C99_LIMIT_MACRO_0543 543
#define C99_LIMIT_MACRO_0544 544
#define C99_LIMIT_MACRO_0545 545
#define C99_LIMIT_MACRO_0546 546
#define C99_LIMIT_MACRO_0547 547
#define C99_LIMIT_MACRO_0548 548
#define C99_LIMIT_MACRO_0549 549
#define C99_LIMIT_MACRO_0550 550
#define C99_LIMIT_MACRO_0551 551
#define C99_LIMIT_MACRO_0552 552
#define C99_LIMIT_MACRO_0553 553
#define C99_LIMIT_MACRO_0554 554
#define C99_LIMIT_MACRO_0555 555
#define C99_LIMIT_MACRO_0556 556
#define C99_LIMIT_MACRO_0557 557
#define C99_LIMIT_MACRO_0558 558
#define C99_LIMIT_MACRO_0559 559
#define C99_LIMIT_MACRO_0560 560
#define C99_LIMIT_MACRO_0561 561
#define C99_LIMIT_MACRO_0562 562
#define C99_LIMIT_MACRO_0563 563
#define C99_LIMIT_MACRO_0564 564
#define C99_LIMIT_MACRO_0565 565
#define C99_LIMIT_MACRO_0566 566
#define C99_LIMIT_MACRO_0567 567
#define C99_LIMIT_MACRO_0568 568
#define C99_LIMIT_MACRO_0569 569
#define C99_LIMIT_MACRO_0570 570
#define C99_LIMIT_MACRO_0571 571
#define C99_LIMIT_MACRO_0572 572
#define C99_LIMIT_MACRO_0573 573
#define C99_LIMIT_MACRO_0574 574
#define C99_LIMIT_MACRO_0575 575
#define C99_LIMIT_MACRO_0576 576
#define C99_LIMIT_MACRO_0577 577
#define C99_LIMIT_MACRO_0578 578
#define C99_LIMIT_MACRO_0579 579
#define C99_LIMIT_MACRO_0580 580
#define C99_LIMIT_MACRO_0581 581
#define C99_LIMIT_MACRO_0582 582
#define C99_LIMIT_MACRO_0583 583
#define C99_LIMIT_MACRO_0584 584
#define C99_LIMIT_MACRO_0585 585
#define C99_LIMIT_MACRO_0586 586
#define C99_LIMIT_MACRO_0587 587
#define C99_LIMIT_MACRO_0588 588
#define C99_LIMIT_MACRO_0589 589
#define C99_LIMIT_MACRO_0590 590
#define C99_LIMIT_MACRO_0591 591
#define C99_LIMIT_MACRO_0592 592
#define C99_LIMIT_MACRO_0593 593
#define C99_LIMIT_MACRO_0594 594
#define C99_LIMIT_MACRO_0595 595
#define C99_LIMIT_MACRO_0596 596
#define C99_LIMIT_MACRO_0597 597
#define C99_LIMIT_MACRO_0598 598
#define C99_LIMIT_MACRO_0599 599
#define C99_LIMIT_MACRO_0600 600
#define C99_LIMIT_MACRO_0601 601
#define C99_LIMIT_MACRO_0602 602
#define C99_LIMIT_MACRO_0603 603
#define C99_LIMIT_MACRO_0604 604
#define C99_LIMIT_MACRO_0605 605
#define C99_LIMIT_MACRO_0606 606
#define C99_LIMIT_MACRO_0607 607
#define C99_LIMIT_MACRO_0608 608
#define C99_LIMIT_MACRO_0609 609
#define C99_LIMIT_MACRO_0610 610
#define C99_LIMIT_MACRO_0611 611
#define C99_LIMIT_MACRO_0612 612
#define C99_LIMIT_MACRO_0613 613
#define C99_LIMIT_MACRO_0614 614
#define C99_LIMIT_MACRO_0615 615
#define C99_LIMIT_MACRO_0616 616
#define C99_LIMIT_MACRO_0617 617
#define C99_LIMIT_MACRO_0618 618
#define C99_LIMIT_MACRO_0619 619
#define C99_LIMIT_MACRO_0620 620
#define C99_LIMIT_MACRO_0621 621
#define C99_LIMIT_MACRO_0622 622
#define C99_LIMIT_MACRO_0623 623
#define C99_LIMIT_MACRO_0624 624
#define C99_LIMIT_MACRO_0625 625
#define C99_LIMIT_MACRO_0626 626
#define C99_LIMIT_MACRO_0627 627
#define C99_LIMIT_MACRO_0628 628
#define C99_LIMIT_MACRO_0629 629
#define C99_LIMIT_MACRO_0630 630
#define C99_LIMIT_MACRO_0631 631
#define C99_LIMIT_MACRO_0632 632
#define C99_LIMIT_MACRO_0633 633
#define C99_LIMIT_MACRO_0634 634
#define C99_LIMIT_MACRO_0635 635
#define C99_LIMIT_MACRO_0636 636
#define C99_LIMIT_MACRO_0637 637
#define C99_LIMIT_MACRO_0638 638
#define C99_LIMIT_MACRO_0639 639
#define C99_LIMIT_MACRO_0640 640
#define C99_LIMIT_MACRO_0641 641
#define C99_LIMIT_MACRO_0642 642
#define C99_LIMIT_MACRO_0643 643
#define C99_LIMIT_MACRO_0644 644
#define C99_LIMIT_MACRO_0645 645
#define C99_LIMIT_MACRO_0646 646
#define C99_LIMIT_MACRO_0647 647
#define C99_LIMIT_MACRO_0648 648
#define C99_LIMIT_MACRO_0649 649
#define C99_LIMIT_MACRO_0650 650
#define C99_LIMIT_MACRO_0651 651
#define C99_LIMIT_MACRO_0652 652
#define C99_LIMIT_MACRO_0653 653
#define C99_LIMIT_MACRO_0654 654
#define C99_LIMIT_MACRO_0655 655
#define C99_LIMIT_MACRO_0656 656
#define C99_LIMIT_MACRO_0657 657
#define C99_LIMIT_MACRO_0658 658
#define C99_LIMIT_MACRO_0659 659
#define C99_LIMIT_MACRO_0660 660
#define C99_LIMIT_MACRO_0661 661
#define C99_LIMIT_MACRO_0662 662
#define C99_LIMIT_MACRO_0663 663
#define C99_LIMIT_MACRO_0664 664
#define C99_LIMIT_MACRO_0665 665
#define C99_LIMIT_MACRO_0666 666
#define C99_LIMIT_MACRO_0667 667
#define C99_LIMIT_MACRO_0668 668
#define C99_LIMIT_MACRO_0669 669
#define C99_LIMIT_MACRO_0670 670
#define C99_LIMIT_MACRO_0671 671
#define C99_LIMIT_MACRO_0672 672
#define C99_LIMIT_MACRO_0673 673
#define C99_LIMIT_MACRO_0674 674
#define C99_LIMIT_MACRO_0675 675
#define C99_LIMIT_MACRO_0676 676
#define C99_LIMIT_MACRO_0677 677
#define C99_LIMIT_MACRO_0678 678
#define C99_LIMIT_MACRO_0679 679
#define C99_LIMIT_MACRO_0680 680
#define C99_LIMIT_MACRO_0681 681
#define C99_LIMIT_MACRO_0682 682
#define C99_LIMIT_MACRO_0683 683
#define C99_LIMIT_MACRO_0684 684
#define C99_LIMIT_MACRO_0685 685
#define C99_LIMIT_MACRO_0686 686
#define C99_LIMIT_MACRO_0687 687
#define C99_LIMIT_MACRO_0688 688
#define C99_LIMIT_MACRO_0689 689
#define C99_LIMIT_MACRO_0690 690
#define C99_LIMIT_MACRO_0691 691
#define C99_LIMIT_MACRO_0692 692
#define C99_LIMIT_MACRO_0693 693
#define C99_LIMIT_MACRO_0694 694
#define C99_LIMIT_MACRO_0695 695
#define C99_LIMIT_MACRO_0696 696
#define C99_LIMIT_MACRO_0697 697
#define C99_LIMIT_MACRO_0698 698
#define C99_LIMIT_MACRO_0699 699
#define C99_LIMIT_MACRO_0700 700
#define C99_LIMIT_MACRO_0701 701
#define C99_LIMIT_MACRO_0702 702
#define C99_LIMIT_MACRO_0703 703
#define C99_LIMIT_MACRO_0704 704
#define C99_LIMIT_MACRO_0705 705
#define C99_LIMIT_MACRO_0706 706
#define C99_LIMIT_MACRO_0707 707
#define C99_LIMIT_MACRO_0708 708
#define C99_LIMIT_MACRO_0709 709
#define C99_LIMIT_MACRO_0710 710
#define C99_LIMIT_MACRO_0711 711
#define C99_LIMIT_MACRO_0712 712
#define C99_LIMIT_MACRO_0713 713
#define C99_LIMIT_MACRO_0714 714
#define C99_LIMIT_MACRO_0715 715
#define C99_LIMIT_MACRO_0716 716
#define C99_LIMIT_MACRO_0717 717
#define C99_LIMIT_MACRO_0718 718
#define C99_LIMIT_MACRO_0719 719
#define C99_LIMIT_MACRO_0720 720
#define C99_LIMIT_MACRO_0721 721
#define C99_LIMIT_MACRO_0722 722
#define C99_LIMIT_MACRO_0723 723
#define C99_LIMIT_MACRO_0724 724
#define C99_LIMIT_MACRO_0725 725
#define C99_LIMIT_MACRO_0726 726
#define C99_LIMIT_MACRO_0727 727
#define C99_LIMIT_MACRO_0728 728
#define C99_LIMIT_MACRO_0729 729
#define C99_LIMIT_MACRO_0730 730
#define C99_LIMIT_MACRO_0731 731
#define C99_LIMIT_MACRO_0732 732
#define C99_LIMIT_MACRO_0733 733
#define C99_LIMIT_MACRO_0734 734
#define C99_LIMIT_MACRO_0735 735
#define C99_LIMIT_MACRO_0736 736
#define C99_LIMIT_MACRO_0737 737
#define C99_LIMIT_MACRO_0738 738
#define C99_LIMIT_MACRO_0739 739
#define C99_LIMIT_MACRO_0740 740
#define C99_LIMIT_MACRO_0741 741
#define C99_LIMIT_MACRO_0742 742
#define C99_LIMIT_MACRO_0743 743
#define C99_LIMIT_MACRO_0744 744
#define C99_LIMIT_MACRO_0745 745
#define C99_LIMIT_MACRO_0746 746
#define C99_LIMIT_MACRO_0747 747
#define C99_LIMIT_MACRO_0748 748
#define C99_LIMIT_MACRO_0749 749
#define C99_LIMIT_MACRO_0750 750
#define C99_LIMIT_MACRO_0751 751
#define C99_LIMIT_MACRO_0752 752
#define C99_LIMIT_MACRO_0753 753
#define C99_LIMIT_MACRO_0754 754
#define C99_LIMIT_MACRO_0755 755
#define C99_LIMIT_MACRO_0756 756
#define C99_LIMIT_MACRO_0757 757
#define C99_LIMIT_MACRO_0758 758
#define C99_LIMIT_MACRO_0759 759
#define C99_LIMIT_MACRO_0760 760
#define C99_LIMIT_MACRO_0761 761
#define C99_LIMIT_MACRO_0762 762
#define C99_LIMIT_MACRO_0763 763
#define C99_LIMIT_MACRO_0764 764
#define C99_LIMIT_MACRO_0765 765
#define C99_LIMIT_MACRO_0766 766
#define C99_LIMIT_MACRO_0767 767
#define C99_LIMIT_MACRO_0768 768
#define C99_LIMIT_MACRO_0769 769
#define C99_LIMIT_MACRO_0770 770
#define C99_LIMIT_MACRO_0771 771
#define C99_LIMIT_MACRO_0772 772
#define C99_LIMIT_MACRO_0773 773
#define C99_LIMIT_MACRO_0774 774
#define C99_LIMIT_MACRO_0775 775
#define C99_LIMIT_MACRO_0776 776
#define C99_LIMIT_MACRO_0777 777
#define C99_LIMIT_MACRO_0778 778
#define C99_LIMIT_MACRO_0779 779
#define C99_LIMIT_MACRO_0780 780
#define C99_LIMIT_MACRO_0781 781
#define C99_LIMIT_MACRO_0782 782
#define C99_LIMIT_MACRO_0783 783
#define C99_LIMIT_MACRO_0784 784
#define C99_LIMIT_MACRO_0785 785
#define C99_LIMIT_MACRO_0786 786
#define C99_LIMIT_MACRO_0787 787
#define C99_LIMIT_MACRO_0788 788
#define C99_LIMIT_MACRO_0789 789
#define C99_LIMIT_MACRO_0790 790
#define C99_LIMIT_MACRO_0791 791
#define C99_LIMIT_MACRO_0792 792
#define C99_LIMIT_MACRO_0793 793
#define C99_LIMIT_MACRO_0794 794
#define C99_LIMIT_MACRO_0795 795
#define C99_LIMIT_MACRO_0796 796
#define C99_LIMIT_MACRO_0797 797
#define C99_LIMIT_MACRO_0798 798
#define C99_LIMIT_MACRO_0799 799
#define C99_LIMIT_MACRO_0800 800
#define C99_LIMIT_MACRO_0801 801
#define C99_LIMIT_MACRO_0802 802
#define C99_LIMIT_MACRO_0803 803
#define C99_LIMIT_MACRO_0804 804
#define C99_LIMIT_MACRO_0805 805
#define C99_LIMIT_MACRO_0806 806
#define C99_LIMIT_MACRO_0807 807
#define C99_LIMIT_MACRO_0808 808
#define C99_LIMIT_MACRO_0809 809
#define C99_LIMIT_MACRO_0810 810
#define C99_LIMIT_MACRO_0811 811
#define C99_LIMIT_MACRO_0812 812
#define C99_LIMIT_MACRO_0813 813
#define C99_LIMIT_MACRO_0814 814
#define C99_LIMIT_MACRO_0815 815
#define C99_LIMIT_MACRO_0816 816
#define C99_LIMIT_MACRO_0817 817
#define C99_LIMIT_MACRO_0818 818
#define C99_LIMIT_MACRO_0819 819
#define C99_LIMIT_MACRO_0820 820
#define C99_LIMIT_MACRO_0821 821
#define C99_LIMIT_MACRO_0822 822
#define C99_LIMIT_MACRO_0823 823
#define C99_LIMIT_MACRO_0824 824
#define C99_LIMIT_MACRO_0825 825
#define C99_LIMIT_MACRO_0826 826
#define C99_LIMIT_MACRO_0827 827
#define C99_LIMIT_MACRO_0828 828
#define C99_LIMIT_MACRO_0829 829
#define C99_LIMIT_MACRO_0830 830
#define C99_LIMIT_MACRO_0831 831
#define C99_LIMIT_MACRO_0832 832
#define C99_LIMIT_MACRO_0833 833
#define C99_LIMIT_MACRO_0834 834
#define C99_LIMIT_MACRO_0835 835
#define C99_LIMIT_MACRO_0836 836
#define C99_LIMIT_MACRO_0837 837
#define C99_LIMIT_MACRO_0838 838
#define C99_LIMIT_MACRO_0839 839
#define C99_LIMIT_MACRO_0840 840
#define C99_LIMIT_MACRO_0841 841
#define C99_LIMIT_MACRO_0842 842
#define C99_LIMIT_MACRO_0843 843
#define C99_LIMIT_MACRO_0844 844
#define C99_LIMIT_MACRO_0845 845
#define C99_LIMIT_MACRO_0846 846
#define C99_LIMIT_MACRO_0847 847
#define C99_LIMIT_MACRO_0848 848
#define C99_LIMIT_MACRO_0849 849
#define C99_LIMIT_MACRO_0850 850
#define C99_LIMIT_MACRO_0851 851
#define C99_LIMIT_MACRO_0852 852
#define C99_LIMIT_MACRO_0853 853
#define C99_LIMIT_MACRO_0854 854
#define C99_LIMIT_MACRO_0855 855
#define C99_LIMIT_MACRO_0856 856
#define C99_LIMIT_MACRO_0857 857
#define C99_LIMIT_MACRO_0858 858
#define C99_LIMIT_MACRO_0859 859
#define C99_LIMIT_MACRO_0860 860
#define C99_LIMIT_MACRO_0861 861
#define C99_LIMIT_MACRO_0862 862
#define C99_LIMIT_MACRO_0863 863
#define C99_LIMIT_MACRO_0864 864
#define C99_LIMIT_MACRO_0865 865
#define C99_LIMIT_MACRO_0866 866
#define C99_LIMIT_MACRO_0867 867
#define C99_LIMIT_MACRO_0868 868
#define C99_LIMIT_MACRO_0869 869
#define C99_LIMIT_MACRO_0870 870
#define C99_LIMIT_MACRO_0871 871
#define C99_LIMIT_MACRO_0872 872
#define C99_LIMIT_MACRO_0873 873
#define C99_LIMIT_MACRO_0874 874
#define C99_LIMIT_MACRO_0875 875
#define C99_LIMIT_MACRO_0876 876
#define C99_LIMIT_MACRO_0877 877
#define C99_LIMIT_MACRO_0878 878
#define C99_LIMIT_MACRO_0879 879
#define C99_LIMIT_MACRO_0880 880
#define C99_LIMIT_MACRO_0881 881
#define C99_LIMIT_MACRO_0882 882
#define C99_LIMIT_MACRO_0883 883
#define C99_LIMIT_MACRO_0884 884
#define C99_LIMIT_MACRO_0885 885
#define C99_LIMIT_MACRO_0886 886
#define C99_LIMIT_MACRO_0887 887
#define C99_LIMIT_MACRO_0888 888
#define C99_LIMIT_MACRO_0889 889
#define C99_LIMIT_MACRO_0890 890
#define C99_LIMIT_MACRO_0891 891
#define C99_LIMIT_MACRO_0892 892
#define C99_LIMIT_MACRO_0893 893
#define C99_LIMIT_MACRO_0894 894
#define C99_LIMIT_MACRO_0895 895
#define C99_LIMIT_MACRO_0896 896
#define C99_LIMIT_MACRO_0897 897
#define C99_LIMIT_MACRO_0898 898
#define C99_LIMIT_MACRO_0899 899
#define C99_LIMIT_MACRO_0900 900
#define C99_LIMIT_MACRO_0901 901
#define C99_LIMIT_MACRO_0902 902
#define C99_LIMIT_MACRO_0903 903
#define C99_LIMIT_MACRO_0904 904
#define C99_LIMIT_MACRO_0905 905
#define C99_LIMIT_MACRO_0906 906
#define C99_LIMIT_MACRO_0907 907
#define C99_LIMIT_MACRO_0908 908
#define C99_LIMIT_MACRO_0909 909
#define C99_LIMIT_MACRO_0910 910
#define C99_LIMIT_MACRO_0911 911
#define C99_LIMIT_MACRO_0912 912
#define C99_LIMIT_MACRO_0913 913
#define C99_LIMIT_MACRO_0914 914
#define C99_LIMIT_MACRO_0915 915
#define C99_LIMIT_MACRO_0916 916
#define C99_LIMIT_MACRO_0917 917
#define C99_LIMIT_MACRO_0918 918
#define C99_LIMIT_MACRO_0919 919
#define C99_LIMIT_MACRO_0920 920
#define C99_LIMIT_MACRO_0921 921
#define C99_LIMIT_MACRO_0922 922
#define C99_LIMIT_MACRO_0923 923
#define C99_LIMIT_MACRO_0924 924
#define C99_LIMIT_MACRO_0925 925
#define C99_LIMIT_MACRO_0926 926
#define C99_LIMIT_MACRO_0927 927
#define C99_LIMIT_MACRO_0928 928
#define C99_LIMIT_MACRO_0929 929
#define C99_LIMIT_MACRO_0930 930
#define C99_LIMIT_MACRO_0931 931
#define C99_LIMIT_MACRO_0932 932
#define C99_LIMIT_MACRO_0933 933
#define C99_LIMIT_MACRO_0934 934
#define C99_LIMIT_MACRO_0935 935
#define C99_LIMIT_MACRO_0936 936
#define C99_LIMIT_MACRO_0937 937
#define C99_LIMIT_MACRO_0938 938
#define C99_LIMIT_MACRO_0939 939
#define C99_LIMIT_MACRO_0940 940
#define C99_LIMIT_MACRO_0941 941
#define C99_LIMIT_MACRO_0942 942
#define C99_LIMIT_MACRO_0943 943
#define C99_LIMIT_MACRO_0944 944
#define C99_LIMIT_MACRO_0945 945
#define C99_LIMIT_MACRO_0946 946
#define C99_LIMIT_MACRO_0947 947
#define C99_LIMIT_MACRO_0948 948
#define C99_LIMIT_MACRO_0949 949
#define C99_LIMIT_MACRO_0950 950
#define C99_LIMIT_MACRO_0951 951
#define C99_LIMIT_MACRO_0952 952
#define C99_LIMIT_MACRO_0953 953
#define C99_LIMIT_MACRO_0954 954
#define C99_LIMIT_MACRO_0955 955
#define C99_LIMIT_MACRO_0956 956
#define C99_LIMIT_MACRO_0957 957
#define C99_LIMIT_MACRO_0958 958
#define C99_LIMIT_MACRO_0959 959
#define C99_LIMIT_MACRO_0960 960
#define C99_LIMIT_MACRO_0961 961
#define C99_LIMIT_MACRO_0962 962
#define C99_LIMIT_MACRO_0963 963
#define C99_LIMIT_MACRO_0964 964
#define C99_LIMIT_MACRO_0965 965
#define C99_LIMIT_MACRO_0966 966
#define C99_LIMIT_MACRO_0967 967
#define C99_LIMIT_MACRO_0968 968
#define C99_LIMIT_MACRO_0969 969
#define C99_LIMIT_MACRO_0970 970
#define C99_LIMIT_MACRO_0971 971
#define C99_LIMIT_MACRO_0972 972
#define C99_LIMIT_MACRO_0973 973
#define C99_LIMIT_MACRO_0974 974
#define C99_LIMIT_MACRO_0975 975
#define C99_LIMIT_MACRO_0976 976
#define C99_LIMIT_MACRO_0977 977
#define C99_LIMIT_MACRO_0978 978
#define C99_LIMIT_MACRO_0979 979
#define C99_LIMIT_MACRO_0980 980
#define C99_LIMIT_MACRO_0981 981
#define C99_LIMIT_MACRO_0982 982
#define C99_LIMIT_MACRO_0983 983
#define C99_LIMIT_MACRO_0984 984
#define C99_LIMIT_MACRO_0985 985
#define C99_LIMIT_MACRO_0986 986
#define C99_LIMIT_MACRO_0987 987
#define C99_LIMIT_MACRO_0988 988
#define C99_LIMIT_MACRO_0989 989
#define C99_LIMIT_MACRO_0990 990
#define C99_LIMIT_MACRO_0991 991
#define C99_LIMIT_MACRO_0992 992
#define C99_LIMIT_MACRO_0993 993
#define C99_LIMIT_MACRO_0994 994
#define C99_LIMIT_MACRO_0995 995
#define C99_LIMIT_MACRO_0996 996
#define C99_LIMIT_MACRO_0997 997
#define C99_LIMIT_MACRO_0998 998
#define C99_LIMIT_MACRO_0999 999
#define C99_LIMIT_MACRO_1000 1000
#define C99_LIMIT_MACRO_1001 1001
#define C99_LIMIT_MACRO_1002 1002
#define C99_LIMIT_MACRO_1003 1003
#define C99_LIMIT_MACRO_1004 1004
#define C99_LIMIT_MACRO_1005 1005
#define C99_LIMIT_MACRO_1006 1006
#define C99_LIMIT_MACRO_1007 1007
#define C99_LIMIT_MACRO_1008 1008
#define C99_LIMIT_MACRO_1009 1009
#define C99_LIMIT_MACRO_1010 1010
#define C99_LIMIT_MACRO_1011 1011
#define C99_LIMIT_MACRO_1012 1012
#define C99_LIMIT_MACRO_1013 1013
#define C99_LIMIT_MACRO_1014 1014
#define C99_LIMIT_MACRO_1015 1015
#define C99_LIMIT_MACRO_1016 1016
#define C99_LIMIT_MACRO_1017 1017
#define C99_LIMIT_MACRO_1018 1018
#define C99_LIMIT_MACRO_1019 1019
#define C99_LIMIT_MACRO_1020 1020
#define C99_LIMIT_MACRO_1021 1021
#define C99_LIMIT_MACRO_1022 1022
#define C99_LIMIT_MACRO_1023 1023
#define C99_LIMIT_MACRO_1024 1024
#define C99_LIMIT_MACRO_1025 1025
#define C99_LIMIT_MACRO_1026 1026
#define C99_LIMIT_MACRO_1027 1027
#define C99_LIMIT_MACRO_1028 1028
#define C99_LIMIT_MACRO_1029 1029
#define C99_LIMIT_MACRO_1030 1030
#define C99_LIMIT_MACRO_1031 1031
#define C99_LIMIT_MACRO_1032 1032
#define C99_LIMIT_MACRO_1033 1033
#define C99_LIMIT_MACRO_1034 1034
#define C99_LIMIT_MACRO_1035 1035
#define C99_LIMIT_MACRO_1036 1036
#define C99_LIMIT_MACRO_1037 1037
#define C99_LIMIT_MACRO_1038 1038
#define C99_LIMIT_MACRO_1039 1039
#define C99_LIMIT_MACRO_1040 1040
#define C99_LIMIT_MACRO_1041 1041
#define C99_LIMIT_MACRO_1042 1042
#define C99_LIMIT_MACRO_1043 1043
#define C99_LIMIT_MACRO_1044 1044
#define C99_LIMIT_MACRO_1045 1045
#define C99_LIMIT_MACRO_1046 1046
#define C99_LIMIT_MACRO_1047 1047
#define C99_LIMIT_MACRO_1048 1048
#define C99_LIMIT_MACRO_1049 1049
#define C99_LIMIT_MACRO_1050 1050
#define C99_LIMIT_MACRO_1051 1051
#define C99_LIMIT_MACRO_1052 1052
#define C99_LIMIT_MACRO_1053 1053
#define C99_LIMIT_MACRO_1054 1054
#define C99_LIMIT_MACRO_1055 1055
#define C99_LIMIT_MACRO_1056 1056
#define C99_LIMIT_MACRO_1057 1057
#define C99_LIMIT_MACRO_1058 1058
#define C99_LIMIT_MACRO_1059 1059
#define C99_LIMIT_MACRO_1060 1060
#define C99_LIMIT_MACRO_1061 1061
#define C99_LIMIT_MACRO_1062 1062
#define C99_LIMIT_MACRO_1063 1063
#define C99_LIMIT_MACRO_1064 1064
#define C99_LIMIT_MACRO_1065 1065
#define C99_LIMIT_MACRO_1066 1066
#define C99_LIMIT_MACRO_1067 1067
#define C99_LIMIT_MACRO_1068 1068
#define C99_LIMIT_MACRO_1069 1069
#define C99_LIMIT_MACRO_1070 1070
#define C99_LIMIT_MACRO_1071 1071
#define C99_LIMIT_MACRO_1072 1072
#define C99_LIMIT_MACRO_1073 1073
#define C99_LIMIT_MACRO_1074 1074
#define C99_LIMIT_MACRO_1075 1075
#define C99_LIMIT_MACRO_1076 1076
#define C99_LIMIT_MACRO_1077 1077
#define C99_LIMIT_MACRO_1078 1078
#define C99_LIMIT_MACRO_1079 1079
#define C99_LIMIT_MACRO_1080 1080
#define C99_LIMIT_MACRO_1081 1081
#define C99_LIMIT_MACRO_1082 1082
#define C99_LIMIT_MACRO_1083 1083
#define C99_LIMIT_MACRO_1084 1084
#define C99_LIMIT_MACRO_1085 1085
#define C99_LIMIT_MACRO_1086 1086
#define C99_LIMIT_MACRO_1087 1087
#define C99_LIMIT_MACRO_1088 1088
#define C99_LIMIT_MACRO_1089 1089
#define C99_LIMIT_MACRO_1090 1090
#define C99_LIMIT_MACRO_1091 1091
#define C99_LIMIT_MACRO_1092 1092
#define C99_LIMIT_MACRO_1093 1093
#define C99_LIMIT_MACRO_1094 1094
#define C99_LIMIT_MACRO_1095 1095
#define C99_LIMIT_MACRO_1096 1096
#define C99_LIMIT_MACRO_1097 1097
#define C99_LIMIT_MACRO_1098 1098
#define C99_LIMIT_MACRO_1099 1099
#define C99_LIMIT_MACRO_1100 1100
#define C99_LIMIT_MACRO_1101 1101
#define C99_LIMIT_MACRO_1102 1102
#define C99_LIMIT_MACRO_1103 1103
#define C99_LIMIT_MACRO_1104 1104
#define C99_LIMIT_MACRO_1105 1105
#define C99_LIMIT_MACRO_1106 1106
#define C99_LIMIT_MACRO_1107 1107
#define C99_LIMIT_MACRO_1108 1108
#define C99_LIMIT_MACRO_1109 1109
#define C99_LIMIT_MACRO_1110 1110
#define C99_LIMIT_MACRO_1111 1111
#define C99_LIMIT_MACRO_1112 1112
#define C99_LIMIT_MACRO_1113 1113
#define C99_LIMIT_MACRO_1114 1114
#define C99_LIMIT_MACRO_1115 1115
#define C99_LIMIT_MACRO_1116 1116
#define C99_LIMIT_MACRO_1117 1117
#define C99_LIMIT_MACRO_1118 1118
#define C99_LIMIT_MACRO_1119 1119
#define C99_LIMIT_MACRO_1120 1120
#define C99_LIMIT_MACRO_1121 1121
#define C99_LIMIT_MACRO_1122 1122
#define C99_LIMIT_MACRO_1123 1123
#define C99_LIMIT_MACRO_1124 1124
#define C99_LIMIT_MACRO_1125 1125
#define C99_LIMIT_MACRO_1126 1126
#define C99_LIMIT_MACRO_1127 1127
#define C99_LIMIT_MACRO_1128 1128
#define C99_LIMIT_MACRO_1129 1129
#define C99_LIMIT_MACRO_1130 1130
#define C99_LIMIT_MACRO_1131 1131
#define C99_LIMIT_MACRO_1132 1132
#define C99_LIMIT_MACRO_1133 1133
#define C99_LIMIT_MACRO_1134 1134
#define C99_LIMIT_MACRO_1135 1135
#define C99_LIMIT_MACRO_1136 1136
#define C99_LIMIT_MACRO_1137 1137
#define C99_LIMIT_MACRO_1138 1138
#define C99_LIMIT_MACRO_1139 1139
#define C99_LIMIT_MACRO_1140 1140
#define C99_LIMIT_MACRO_1141 1141
#define C99_LIMIT_MACRO_1142 1142
#define C99_LIMIT_MACRO_1143 1143
#define C99_LIMIT_MACRO_1144 1144
#define C99_LIMIT_MACRO_1145 1145
#define C99_LIMIT_MACRO_1146 1146
#define C99_LIMIT_MACRO_1147 1147
#define C99_LIMIT_MACRO_1148 1148
#define C99_LIMIT_MACRO_1149 1149
#define C99_LIMIT_MACRO_1150 1150
#define C99_LIMIT_MACRO_1151 1151
#define C99_LIMIT_MACRO_1152 1152
#define C99_LIMIT_MACRO_1153 1153
#define C99_LIMIT_MACRO_1154 1154
#define C99_LIMIT_MACRO_1155 1155
#define C99_LIMIT_MACRO_1156 1156
#define C99_LIMIT_MACRO_1157 1157
#define C99_LIMIT_MACRO_1158 1158
#define C99_LIMIT_MACRO_1159 1159
#define C99_LIMIT_MACRO_1160 1160
#define C99_LIMIT_MACRO_1161 1161
#define C99_LIMIT_MACRO_1162 1162
#define C99_LIMIT_MACRO_1163 1163
#define C99_LIMIT_MACRO_1164 1164
#define C99_LIMIT_MACRO_1165 1165
#define C99_LIMIT_MACRO_1166 1166
#define C99_LIMIT_MACRO_1167 1167
#define C99_LIMIT_MACRO_1168 1168
#define C99_LIMIT_MACRO_1169 1169
#define C99_LIMIT_MACRO_1170 1170
#define C99_LIMIT_MACRO_1171 1171
#define C99_LIMIT_MACRO_1172 1172
#define C99_LIMIT_MACRO_1173 1173
#define C99_LIMIT_MACRO_1174 1174
#define C99_LIMIT_MACRO_1175 1175
#define C99_LIMIT_MACRO_1176 1176
#define C99_LIMIT_MACRO_1177 1177
#define C99_LIMIT_MACRO_1178 1178
#define C99_LIMIT_MACRO_1179 1179
#define C99_LIMIT_MACRO_1180 1180
#define C99_LIMIT_MACRO_1181 1181
#define C99_LIMIT_MACRO_1182 1182
#define C99_LIMIT_MACRO_1183 1183
#define C99_LIMIT_MACRO_1184 1184
#define C99_LIMIT_MACRO_1185 1185
#define C99_LIMIT_MACRO_1186 1186
#define C99_LIMIT_MACRO_1187 1187
#define C99_LIMIT_MACRO_1188 1188
#define C99_LIMIT_MACRO_1189 1189
#define C99_LIMIT_MACRO_1190 1190
#define C99_LIMIT_MACRO_1191 1191
#define C99_LIMIT_MACRO_1192 1192
#define C99_LIMIT_MACRO_1193 1193
#define C99_LIMIT_MACRO_1194 1194
#define C99_LIMIT_MACRO_1195 1195
#define C99_LIMIT_MACRO_1196 1196
#define C99_LIMIT_MACRO_1197 1197
#define C99_LIMIT_MACRO_1198 1198
#define C99_LIMIT_MACRO_1199 1199
#define C99_LIMIT_MACRO_1200 1200
#define C99_LIMIT_MACRO_1201 1201
#define C99_LIMIT_MACRO_1202 1202
#define C99_LIMIT_MACRO_1203 1203
#define C99_LIMIT_MACRO_1204 1204
#define C99_LIMIT_MACRO_1205 1205
#define C99_LIMIT_MACRO_1206 1206
#define C99_LIMIT_MACRO_1207 1207
#define C99_LIMIT_MACRO_1208 1208
#define C99_LIMIT_MACRO_1209 1209
#define C99_LIMIT_MACRO_1210 1210
#define C99_LIMIT_MACRO_1211 1211
#define C99_LIMIT_MACRO_1212 1212
#define C99_LIMIT_MACRO_1213 1213
#define C99_LIMIT_MACRO_1214 1214
#define C99_LIMIT_MACRO_1215 1215
#define C99_LIMIT_MACRO_1216 1216
#define C99_LIMIT_MACRO_1217 1217
#define C99_LIMIT_MACRO_1218 1218
#define C99_LIMIT_MACRO_1219 1219
#define C99_LIMIT_MACRO_1220 1220
#define C99_LIMIT_MACRO_1221 1221
#define C99_LIMIT_MACRO_1222 1222
#define C99_LIMIT_MACRO_1223 1223
#define C99_LIMIT_MACRO_1224 1224
#define C99_LIMIT_MACRO_1225 1225
#define C99_LIMIT_MACRO_1226 1226
#define C99_LIMIT_MACRO_1227 1227
#define C99_LIMIT_MACRO_1228 1228
#define C99_LIMIT_MACRO_1229 1229
#define C99_LIMIT_MACRO_1230 1230
#define C99_LIMIT_MACRO_1231 1231
#define C99_LIMIT_MACRO_1232 1232
#define C99_LIMIT_MACRO_1233 1233
#define C99_LIMIT_MACRO_1234 1234
#define C99_LIMIT_MACRO_1235 1235
#define C99_LIMIT_MACRO_1236 1236
#define C99_LIMIT_MACRO_1237 1237
#define C99_LIMIT_MACRO_1238 1238
#define C99_LIMIT_MACRO_1239 1239
#define C99_LIMIT_MACRO_1240 1240
#define C99_LIMIT_MACRO_1241 1241
#define C99_LIMIT_MACRO_1242 1242
#define C99_LIMIT_MACRO_1243 1243
#define C99_LIMIT_MACRO_1244 1244
#define C99_LIMIT_MACRO_1245 1245
#define C99_LIMIT_MACRO_1246 1246
#define C99_LIMIT_MACRO_1247 1247
#define C99_LIMIT_MACRO_1248 1248
#define C99_LIMIT_MACRO_1249 1249
#define C99_LIMIT_MACRO_1250 1250
#define C99_LIMIT_MACRO_1251 1251
#define C99_LIMIT_MACRO_1252 1252
#define C99_LIMIT_MACRO_1253 1253
#define C99_LIMIT_MACRO_1254 1254
#define C99_LIMIT_MACRO_1255 1255
#define C99_LIMIT_MACRO_1256 1256
#define C99_LIMIT_MACRO_1257 1257
#define C99_LIMIT_MACRO_1258 1258
#define C99_LIMIT_MACRO_1259 1259
#define C99_LIMIT_MACRO_1260 1260
#define C99_LIMIT_MACRO_1261 1261
#define C99_LIMIT_MACRO_1262 1262
#define C99_LIMIT_MACRO_1263 1263
#define C99_LIMIT_MACRO_1264 1264
#define C99_LIMIT_MACRO_1265 1265
#define C99_LIMIT_MACRO_1266 1266
#define C99_LIMIT_MACRO_1267 1267
#define C99_LIMIT_MACRO_1268 1268
#define C99_LIMIT_MACRO_1269 1269
#define C99_LIMIT_MACRO_1270 1270
#define C99_LIMIT_MACRO_1271 1271
#define C99_LIMIT_MACRO_1272 1272
#define C99_LIMIT_MACRO_1273 1273
#define C99_LIMIT_MACRO_1274 1274
#define C99_LIMIT_MACRO_1275 1275
#define C99_LIMIT_MACRO_1276 1276
#define C99_LIMIT_MACRO_1277 1277
#define C99_LIMIT_MACRO_1278 1278
#define C99_LIMIT_MACRO_1279 1279
#define C99_LIMIT_MACRO_1280 1280
#define C99_LIMIT_MACRO_1281 1281
#define C99_LIMIT_MACRO_1282 1282
#define C99_LIMIT_MACRO_1283 1283
#define C99_LIMIT_MACRO_1284 1284
#define C99_LIMIT_MACRO_1285 1285
#define C99_LIMIT_MACRO_1286 1286
#define C99_LIMIT_MACRO_1287 1287
#define C99_LIMIT_MACRO_1288 1288
#define C99_LIMIT_MACRO_1289 1289
#define C99_LIMIT_MACRO_1290 1290
#define C99_LIMIT_MACRO_1291 1291
#define C99_LIMIT_MACRO_1292 1292
#define C99_LIMIT_MACRO_1293 1293
#define C99_LIMIT_MACRO_1294 1294
#define C99_LIMIT_MACRO_1295 1295
#define C99_LIMIT_MACRO_1296 1296
#define C99_LIMIT_MACRO_1297 1297
#define C99_LIMIT_MACRO_1298 1298
#define C99_LIMIT_MACRO_1299 1299
#define C99_LIMIT_MACRO_1300 1300
#define C99_LIMIT_MACRO_1301 1301
#define C99_LIMIT_MACRO_1302 1302
#define C99_LIMIT_MACRO_1303 1303
#define C99_LIMIT_MACRO_1304 1304
#define C99_LIMIT_MACRO_1305 1305
#define C99_LIMIT_MACRO_1306 1306
#define C99_LIMIT_MACRO_1307 1307
#define C99_LIMIT_MACRO_1308 1308
#define C99_LIMIT_MACRO_1309 1309
#define C99_LIMIT_MACRO_1310 1310
#define C99_LIMIT_MACRO_1311 1311
#define C99_LIMIT_MACRO_1312 1312
#define C99_LIMIT_MACRO_1313 1313
#define C99_LIMIT_MACRO_1314 1314
#define C99_LIMIT_MACRO_1315 1315
#define C99_LIMIT_MACRO_1316 1316
#define C99_LIMIT_MACRO_1317 1317
#define C99_LIMIT_MACRO_1318 1318
#define C99_LIMIT_MACRO_1319 1319
#define C99_LIMIT_MACRO_1320 1320
#define C99_LIMIT_MACRO_1321 1321
#define C99_LIMIT_MACRO_1322 1322
#define C99_LIMIT_MACRO_1323 1323
#define C99_LIMIT_MACRO_1324 1324
#define C99_LIMIT_MACRO_1325 1325
#define C99_LIMIT_MACRO_1326 1326
#define C99_LIMIT_MACRO_1327 1327
#define C99_LIMIT_MACRO_1328 1328
#define C99_LIMIT_MACRO_1329 1329
#define C99_LIMIT_MACRO_1330 1330
#define C99_LIMIT_MACRO_1331 1331
#define C99_LIMIT_MACRO_1332 1332
#define C99_LIMIT_MACRO_1333 1333
#define C99_LIMIT_MACRO_1334 1334
#define C99_LIMIT_MACRO_1335 1335
#define C99_LIMIT_MACRO_1336 1336
#define C99_LIMIT_MACRO_1337 1337
#define C99_LIMIT_MACRO_1338 1338
#define C99_LIMIT_MACRO_1339 1339
#define C99_LIMIT_MACRO_1340 1340
#define C99_LIMIT_MACRO_1341 1341
#define C99_LIMIT_MACRO_1342 1342
#define C99_LIMIT_MACRO_1343 1343
#define C99_LIMIT_MACRO_1344 1344
#define C99_LIMIT_MACRO_1345 1345
#define C99_LIMIT_MACRO_1346 1346
#define C99_LIMIT_MACRO_1347 1347
#define C99_LIMIT_MACRO_1348 1348
#define C99_LIMIT_MACRO_1349 1349
#define C99_LIMIT_MACRO_1350 1350
#define C99_LIMIT_MACRO_1351 1351
#define C99_LIMIT_MACRO_1352 1352
#define C99_LIMIT_MACRO_1353 1353
#define C99_LIMIT_MACRO_1354 1354
#define C99_LIMIT_MACRO_1355 1355
#define C99_LIMIT_MACRO_1356 1356
#define C99_LIMIT_MACRO_1357 1357
#define C99_LIMIT_MACRO_1358 1358
#define C99_LIMIT_MACRO_1359 1359
#define C99_LIMIT_MACRO_1360 1360
#define C99_LIMIT_MACRO_1361 1361
#define C99_LIMIT_MACRO_1362 1362
#define C99_LIMIT_MACRO_1363 1363
#define C99_LIMIT_MACRO_1364 1364
#define C99_LIMIT_MACRO_1365 1365
#define C99_LIMIT_MACRO_1366 1366
#define C99_LIMIT_MACRO_1367 1367
#define C99_LIMIT_MACRO_1368 1368
#define C99_LIMIT_MACRO_1369 1369
#define C99_LIMIT_MACRO_1370 1370
#define C99_LIMIT_MACRO_1371 1371
#define C99_LIMIT_MACRO_1372 1372
#define C99_LIMIT_MACRO_1373 1373
#define C99_LIMIT_MACRO_1374 1374
#define C99_LIMIT_MACRO_1375 1375
#define C99_LIMIT_MACRO_1376 1376
#define C99_LIMIT_MACRO_1377 1377
#define C99_LIMIT_MACRO_1378 1378
#define C99_LIMIT_MACRO_1379 1379
#define C99_LIMIT_MACRO_1380 1380
#define C99_LIMIT_MACRO_1381 1381
#define C99_LIMIT_MACRO_1382 1382
#define C99_LIMIT_MACRO_1383 1383
#define C99_LIMIT_MACRO_1384 1384
#define C99_LIMIT_MACRO_1385 1385
#define C99_LIMIT_MACRO_1386 1386
#define C99_LIMIT_MACRO_1387 1387
#define C99_LIMIT_MACRO_1388 1388
#define C99_LIMIT_MACRO_1389 1389
#define C99_LIMIT_MACRO_1390 1390
#define C99_LIMIT_MACRO_1391 1391
#define C99_LIMIT_MACRO_1392 1392
#define C99_LIMIT_MACRO_1393 1393
#define C99_LIMIT_MACRO_1394 1394
#define C99_LIMIT_MACRO_1395 1395
#define C99_LIMIT_MACRO_1396 1396
#define C99_LIMIT_MACRO_1397 1397
#define C99_LIMIT_MACRO_1398 1398
#define C99_LIMIT_MACRO_1399 1399
#define C99_LIMIT_MACRO_1400 1400
#define C99_LIMIT_MACRO_1401 1401
#define C99_LIMIT_MACRO_1402 1402
#define C99_LIMIT_MACRO_1403 1403
#define C99_LIMIT_MACRO_1404 1404
#define C99_LIMIT_MACRO_1405 1405
#define C99_LIMIT_MACRO_1406 1406
#define C99_LIMIT_MACRO_1407 1407
#define C99_LIMIT_MACRO_1408 1408
#define C99_LIMIT_MACRO_1409 1409
#define C99_LIMIT_MACRO_1410 1410
#define C99_LIMIT_MACRO_1411 1411
#define C99_LIMIT_MACRO_1412 1412
#define C99_LIMIT_MACRO_1413 1413
#define C99_LIMIT_MACRO_1414 1414
#define C99_LIMIT_MACRO_1415 1415
#define C99_LIMIT_MACRO_1416 1416
#define C99_LIMIT_MACRO_1417 1417
#define C99_LIMIT_MACRO_1418 1418
#define C99_LIMIT_MACRO_1419 1419
#define C99_LIMIT_MACRO_1420 1420
#define C99_LIMIT_MACRO_1421 1421
#define C99_LIMIT_MACRO_1422 1422
#define C99_LIMIT_MACRO_1423 1423
#define C99_LIMIT_MACRO_1424 1424
#define C99_LIMIT_MACRO_1425 1425
#define C99_LIMIT_MACRO_1426 1426
#define C99_LIMIT_MACRO_1427 1427
#define C99_LIMIT_MACRO_1428 1428
#define C99_LIMIT_MACRO_1429 1429
#define C99_LIMIT_MACRO_1430 1430
#define C99_LIMIT_MACRO_1431 1431
#define C99_LIMIT_MACRO_1432 1432
#define C99_LIMIT_MACRO_1433 1433
#define C99_LIMIT_MACRO_1434 1434
#define C99_LIMIT_MACRO_1435 1435
#define C99_LIMIT_MACRO_1436 1436
#define C99_LIMIT_MACRO_1437 1437
#define C99_LIMIT_MACRO_1438 1438
#define C99_LIMIT_MACRO_1439 1439
#define C99_LIMIT_MACRO_1440 1440
#define C99_LIMIT_MACRO_1441 1441
#define C99_LIMIT_MACRO_1442 1442
#define C99_LIMIT_MACRO_1443 1443
#define C99_LIMIT_MACRO_1444 1444
#define C99_LIMIT_MACRO_1445 1445
#define C99_LIMIT_MACRO_1446 1446
#define C99_LIMIT_MACRO_1447 1447
#define C99_LIMIT_MACRO_1448 1448
#define C99_LIMIT_MACRO_1449 1449
#define C99_LIMIT_MACRO_1450 1450
#define C99_LIMIT_MACRO_1451 1451
#define C99_LIMIT_MACRO_1452 1452
#define C99_LIMIT_MACRO_1453 1453
#define C99_LIMIT_MACRO_1454 1454
#define C99_LIMIT_MACRO_1455 1455
#define C99_LIMIT_MACRO_1456 1456
#define C99_LIMIT_MACRO_1457 1457
#define C99_LIMIT_MACRO_1458 1458
#define C99_LIMIT_MACRO_1459 1459
#define C99_LIMIT_MACRO_1460 1460
#define C99_LIMIT_MACRO_1461 1461
#define C99_LIMIT_MACRO_1462 1462
#define C99_LIMIT_MACRO_1463 1463
#define C99_LIMIT_MACRO_1464 1464
#define C99_LIMIT_MACRO_1465 1465
#define C99_LIMIT_MACRO_1466 1466
#define C99_LIMIT_MACRO_1467 1467
#define C99_LIMIT_MACRO_1468 1468
#define C99_LIMIT_MACRO_1469 1469
#define C99_LIMIT_MACRO_1470 1470
#define C99_LIMIT_MACRO_1471 1471
#define C99_LIMIT_MACRO_1472 1472
#define C99_LIMIT_MACRO_1473 1473
#define C99_LIMIT_MACRO_1474 1474
#define C99_LIMIT_MACRO_1475 1475
#define C99_LIMIT_MACRO_1476 1476
#define C99_LIMIT_MACRO_1477 1477
#define C99_LIMIT_MACRO_1478 1478
#define C99_LIMIT_MACRO_1479 1479
#define C99_LIMIT_MACRO_1480 1480
#define C99_LIMIT_MACRO_1481 1481
#define C99_LIMIT_MACRO_1482 1482
#define C99_LIMIT_MACRO_1483 1483
#define C99_LIMIT_MACRO_1484 1484
#define C99_LIMIT_MACRO_1485 1485
#define C99_LIMIT_MACRO_1486 1486
#define C99_LIMIT_MACRO_1487 1487
#define C99_LIMIT_MACRO_1488 1488
#define C99_LIMIT_MACRO_1489 1489
#define C99_LIMIT_MACRO_1490 1490
#define C99_LIMIT_MACRO_1491 1491
#define C99_LIMIT_MACRO_1492 1492
#define C99_LIMIT_MACRO_1493 1493
#define C99_LIMIT_MACRO_1494 1494
#define C99_LIMIT_MACRO_1495 1495
#define C99_LIMIT_MACRO_1496 1496
#define C99_LIMIT_MACRO_1497 1497
#define C99_LIMIT_MACRO_1498 1498
#define C99_LIMIT_MACRO_1499 1499
#define C99_LIMIT_MACRO_1500 1500
#define C99_LIMIT_MACRO_1501 1501
#define C99_LIMIT_MACRO_1502 1502
#define C99_LIMIT_MACRO_1503 1503
#define C99_LIMIT_MACRO_1504 1504
#define C99_LIMIT_MACRO_1505 1505
#define C99_LIMIT_MACRO_1506 1506
#define C99_LIMIT_MACRO_1507 1507
#define C99_LIMIT_MACRO_1508 1508
#define C99_LIMIT_MACRO_1509 1509
#define C99_LIMIT_MACRO_1510 1510
#define C99_LIMIT_MACRO_1511 1511
#define C99_LIMIT_MACRO_1512 1512
#define C99_LIMIT_MACRO_1513 1513
#define C99_LIMIT_MACRO_1514 1514
#define C99_LIMIT_MACRO_1515 1515
#define C99_LIMIT_MACRO_1516 1516
#define C99_LIMIT_MACRO_1517 1517
#define C99_LIMIT_MACRO_1518 1518
#define C99_LIMIT_MACRO_1519 1519
#define C99_LIMIT_MACRO_1520 1520
#define C99_LIMIT_MACRO_1521 1521
#define C99_LIMIT_MACRO_1522 1522
#define C99_LIMIT_MACRO_1523 1523
#define C99_LIMIT_MACRO_1524 1524
#define C99_LIMIT_MACRO_1525 1525
#define C99_LIMIT_MACRO_1526 1526
#define C99_LIMIT_MACRO_1527 1527
#define C99_LIMIT_MACRO_1528 1528
#define C99_LIMIT_MACRO_1529 1529
#define C99_LIMIT_MACRO_1530 1530
#define C99_LIMIT_MACRO_1531 1531
#define C99_LIMIT_MACRO_1532 1532
#define C99_LIMIT_MACRO_1533 1533
#define C99_LIMIT_MACRO_1534 1534
#define C99_LIMIT_MACRO_1535 1535
#define C99_LIMIT_MACRO_1536 1536
#define C99_LIMIT_MACRO_1537 1537
#define C99_LIMIT_MACRO_1538 1538
#define C99_LIMIT_MACRO_1539 1539
#define C99_LIMIT_MACRO_1540 1540
#define C99_LIMIT_MACRO_1541 1541
#define C99_LIMIT_MACRO_1542 1542
#define C99_LIMIT_MACRO_1543 1543
#define C99_LIMIT_MACRO_1544 1544
#define C99_LIMIT_MACRO_1545 1545
#define C99_LIMIT_MACRO_1546 1546
#define C99_LIMIT_MACRO_1547 1547
#define C99_LIMIT_MACRO_1548 1548
#define C99_LIMIT_MACRO_1549 1549
#define C99_LIMIT_MACRO_1550 1550
#define C99_LIMIT_MACRO_1551 1551
#define C99_LIMIT_MACRO_1552 1552
#define C99_LIMIT_MACRO_1553 1553
#define C99_LIMIT_MACRO_1554 1554
#define C99_LIMIT_MACRO_1555 1555
#define C99_LIMIT_MACRO_1556 1556
#define C99_LIMIT_MACRO_1557 1557
#define C99_LIMIT_MACRO_1558 1558
#define C99_LIMIT_MACRO_1559 1559
#define C99_LIMIT_MACRO_1560 1560
#define C99_LIMIT_MACRO_1561 1561
#define C99_LIMIT_MACRO_1562 1562
#define C99_LIMIT_MACRO_1563 1563
#define C99_LIMIT_MACRO_1564 1564
#define C99_LIMIT_MACRO_1565 1565
#define C99_LIMIT_MACRO_1566 1566
#define C99_LIMIT_MACRO_1567 1567
#define C99_LIMIT_MACRO_1568 1568
#define C99_LIMIT_MACRO_1569 1569
#define C99_LIMIT_MACRO_1570 1570
#define C99_LIMIT_MACRO_1571 1571
#define C99_LIMIT_MACRO_1572 1572
#define C99_LIMIT_MACRO_1573 1573
#define C99_LIMIT_MACRO_1574 1574
#define C99_LIMIT_MACRO_1575 1575
#define C99_LIMIT_MACRO_1576 1576
#define C99_LIMIT_MACRO_1577 1577
#define C99_LIMIT_MACRO_1578 1578
#define C99_LIMIT_MACRO_1579 1579
#define C99_LIMIT_MACRO_1580 1580
#define C99_LIMIT_MACRO_1581 1581
#define C99_LIMIT_MACRO_1582 1582
#define C99_LIMIT_MACRO_1583 1583
#define C99_LIMIT_MACRO_1584 1584
#define C99_LIMIT_MACRO_1585 1585
#define C99_LIMIT_MACRO_1586 1586
#define C99_LIMIT_MACRO_1587 1587
#define C99_LIMIT_MACRO_1588 1588
#define C99_LIMIT_MACRO_1589 1589
#define C99_LIMIT_MACRO_1590 1590
#define C99_LIMIT_MACRO_1591 1591
#define C99_LIMIT_MACRO_1592 1592
#define C99_LIMIT_MACRO_1593 1593
#define C99_LIMIT_MACRO_1594 1594
#define C99_LIMIT_MACRO_1595 1595
#define C99_LIMIT_MACRO_1596 1596
#define C99_LIMIT_MACRO_1597 1597
#define C99_LIMIT_MACRO_1598 1598
#define C99_LIMIT_MACRO_1599 1599
#define C99_LIMIT_MACRO_1600 1600
#define C99_LIMIT_MACRO_1601 1601
#define C99_LIMIT_MACRO_1602 1602
#define C99_LIMIT_MACRO_1603 1603
#define C99_LIMIT_MACRO_1604 1604
#define C99_LIMIT_MACRO_1605 1605
#define C99_LIMIT_MACRO_1606 1606
#define C99_LIMIT_MACRO_1607 1607
#define C99_LIMIT_MACRO_1608 1608
#define C99_LIMIT_MACRO_1609 1609
#define C99_LIMIT_MACRO_1610 1610
#define C99_LIMIT_MACRO_1611 1611
#define C99_LIMIT_MACRO_1612 1612
#define C99_LIMIT_MACRO_1613 1613
#define C99_LIMIT_MACRO_1614 1614
#define C99_LIMIT_MACRO_1615 1615
#define C99_LIMIT_MACRO_1616 1616
#define C99_LIMIT_MACRO_1617 1617
#define C99_LIMIT_MACRO_1618 1618
#define C99_LIMIT_MACRO_1619 1619
#define C99_LIMIT_MACRO_1620 1620
#define C99_LIMIT_MACRO_1621 1621
#define C99_LIMIT_MACRO_1622 1622
#define C99_LIMIT_MACRO_1623 1623
#define C99_LIMIT_MACRO_1624 1624
#define C99_LIMIT_MACRO_1625 1625
#define C99_LIMIT_MACRO_1626 1626
#define C99_LIMIT_MACRO_1627 1627
#define C99_LIMIT_MACRO_1628 1628
#define C99_LIMIT_MACRO_1629 1629
#define C99_LIMIT_MACRO_1630 1630
#define C99_LIMIT_MACRO_1631 1631
#define C99_LIMIT_MACRO_1632 1632
#define C99_LIMIT_MACRO_1633 1633
#define C99_LIMIT_MACRO_1634 1634
#define C99_LIMIT_MACRO_1635 1635
#define C99_LIMIT_MACRO_1636 1636
#define C99_LIMIT_MACRO_1637 1637
#define C99_LIMIT_MACRO_1638 1638
#define C99_LIMIT_MACRO_1639 1639
#define C99_LIMIT_MACRO_1640 1640
#define C99_LIMIT_MACRO_1641 1641
#define C99_LIMIT_MACRO_1642 1642
#define C99_LIMIT_MACRO_1643 1643
#define C99_LIMIT_MACRO_1644 1644
#define C99_LIMIT_MACRO_1645 1645
#define C99_LIMIT_MACRO_1646 1646
#define C99_LIMIT_MACRO_1647 1647
#define C99_LIMIT_MACRO_1648 1648
#define C99_LIMIT_MACRO_1649 1649
#define C99_LIMIT_MACRO_1650 1650
#define C99_LIMIT_MACRO_1651 1651
#define C99_LIMIT_MACRO_1652 1652
#define C99_LIMIT_MACRO_1653 1653
#define C99_LIMIT_MACRO_1654 1654
#define C99_LIMIT_MACRO_1655 1655
#define C99_LIMIT_MACRO_1656 1656
#define C99_LIMIT_MACRO_1657 1657
#define C99_LIMIT_MACRO_1658 1658
#define C99_LIMIT_MACRO_1659 1659
#define C99_LIMIT_MACRO_1660 1660
#define C99_LIMIT_MACRO_1661 1661
#define C99_LIMIT_MACRO_1662 1662
#define C99_LIMIT_MACRO_1663 1663
#define C99_LIMIT_MACRO_1664 1664
#define C99_LIMIT_MACRO_1665 1665
#define C99_LIMIT_MACRO_1666 1666
#define C99_LIMIT_MACRO_1667 1667
#define C99_LIMIT_MACRO_1668 1668
#define C99_LIMIT_MACRO_1669 1669
#define C99_LIMIT_MACRO_1670 1670
#define C99_LIMIT_MACRO_1671 1671
#define C99_LIMIT_MACRO_1672 1672
#define C99_LIMIT_MACRO_1673 1673
#define C99_LIMIT_MACRO_1674 1674
#define C99_LIMIT_MACRO_1675 1675
#define C99_LIMIT_MACRO_1676 1676
#define C99_LIMIT_MACRO_1677 1677
#define C99_LIMIT_MACRO_1678 1678
#define C99_LIMIT_MACRO_1679 1679
#define C99_LIMIT_MACRO_1680 1680
#define C99_LIMIT_MACRO_1681 1681
#define C99_LIMIT_MACRO_1682 1682
#define C99_LIMIT_MACRO_1683 1683
#define C99_LIMIT_MACRO_1684 1684
#define C99_LIMIT_MACRO_1685 1685
#define C99_LIMIT_MACRO_1686 1686
#define C99_LIMIT_MACRO_1687 1687
#define C99_LIMIT_MACRO_1688 1688
#define C99_LIMIT_MACRO_1689 1689
#define C99_LIMIT_MACRO_1690 1690
#define C99_LIMIT_MACRO_1691 1691
#define C99_LIMIT_MACRO_1692 1692
#define C99_LIMIT_MACRO_1693 1693
#define C99_LIMIT_MACRO_1694 1694
#define C99_LIMIT_MACRO_1695 1695
#define C99_LIMIT_MACRO_1696 1696
#define C99_LIMIT_MACRO_1697 1697
#define C99_LIMIT_MACRO_1698 1698
#define C99_LIMIT_MACRO_1699 1699
#define C99_LIMIT_MACRO_1700 1700
#define C99_LIMIT_MACRO_1701 1701
#define C99_LIMIT_MACRO_1702 1702
#define C99_LIMIT_MACRO_1703 1703
#define C99_LIMIT_MACRO_1704 1704
#define C99_LIMIT_MACRO_1705 1705
#define C99_LIMIT_MACRO_1706 1706
#define C99_LIMIT_MACRO_1707 1707
#define C99_LIMIT_MACRO_1708 1708
#define C99_LIMIT_MACRO_1709 1709
#define C99_LIMIT_MACRO_1710 1710
#define C99_LIMIT_MACRO_1711 1711
#define C99_LIMIT_MACRO_1712 1712
#define C99_LIMIT_MACRO_1713 1713
#define C99_LIMIT_MACRO_1714 1714
#define C99_LIMIT_MACRO_1715 1715
#define C99_LIMIT_MACRO_1716 1716
#define C99_LIMIT_MACRO_1717 1717
#define C99_LIMIT_MACRO_1718 1718
#define C99_LIMIT_MACRO_1719 1719
#define C99_LIMIT_MACRO_1720 1720
#define C99_LIMIT_MACRO_1721 1721
#define C99_LIMIT_MACRO_1722 1722
#define C99_LIMIT_MACRO_1723 1723
#define C99_LIMIT_MACRO_1724 1724
#define C99_LIMIT_MACRO_1725 1725
#define C99_LIMIT_MACRO_1726 1726
#define C99_LIMIT_MACRO_1727 1727
#define C99_LIMIT_MACRO_1728 1728
#define C99_LIMIT_MACRO_1729 1729
#define C99_LIMIT_MACRO_1730 1730
#define C99_LIMIT_MACRO_1731 1731
#define C99_LIMIT_MACRO_1732 1732
#define C99_LIMIT_MACRO_1733 1733
#define C99_LIMIT_MACRO_1734 1734
#define C99_LIMIT_MACRO_1735 1735
#define C99_LIMIT_MACRO_1736 1736
#define C99_LIMIT_MACRO_1737 1737
#define C99_LIMIT_MACRO_1738 1738
#define C99_LIMIT_MACRO_1739 1739
#define C99_LIMIT_MACRO_1740 1740
#define C99_LIMIT_MACRO_1741 1741
#define C99_LIMIT_MACRO_1742 1742
#define C99_LIMIT_MACRO_1743 1743
#define C99_LIMIT_MACRO_1744 1744
#define C99_LIMIT_MACRO_1745 1745
#define C99_LIMIT_MACRO_1746 1746
#define C99_LIMIT_MACRO_1747 1747
#define C99_LIMIT_MACRO_1748 1748
#define C99_LIMIT_MACRO_1749 1749
#define C99_LIMIT_MACRO_1750 1750
#define C99_LIMIT_MACRO_1751 1751
#define C99_LIMIT_MACRO_1752 1752
#define C99_LIMIT_MACRO_1753 1753
#define C99_LIMIT_MACRO_1754 1754
#define C99_LIMIT_MACRO_1755 1755
#define C99_LIMIT_MACRO_1756 1756
#define C99_LIMIT_MACRO_1757 1757
#define C99_LIMIT_MACRO_1758 1758
#define C99_LIMIT_MACRO_1759 1759
#define C99_LIMIT_MACRO_1760 1760
#define C99_LIMIT_MACRO_1761 1761
#define C99_LIMIT_MACRO_1762 1762
#define C99_LIMIT_MACRO_1763 1763
#define C99_LIMIT_MACRO_1764 1764
#define C99_LIMIT_MACRO_1765 1765
#define C99_LIMIT_MACRO_1766 1766
#define C99_LIMIT_MACRO_1767 1767
#define C99_LIMIT_MACRO_1768 1768
#define C99_LIMIT_MACRO_1769 1769
#define C99_LIMIT_MACRO_1770 1770
#define C99_LIMIT_MACRO_1771 1771
#define C99_LIMIT_MACRO_1772 1772
#define C99_LIMIT_MACRO_1773 1773
#define C99_LIMIT_MACRO_1774 1774
#define C99_LIMIT_MACRO_1775 1775
#define C99_LIMIT_MACRO_1776 1776
#define C99_LIMIT_MACRO_1777 1777
#define C99_LIMIT_MACRO_1778 1778
#define C99_LIMIT_MACRO_1779 1779
#define C99_LIMIT_MACRO_1780 1780
#define C99_LIMIT_MACRO_1781 1781
#define C99_LIMIT_MACRO_1782 1782
#define C99_LIMIT_MACRO_1783 1783
#define C99_LIMIT_MACRO_1784 1784
#define C99_LIMIT_MACRO_1785 1785
#define C99_LIMIT_MACRO_1786 1786
#define C99_LIMIT_MACRO_1787 1787
#define C99_LIMIT_MACRO_1788 1788
#define C99_LIMIT_MACRO_1789 1789
#define C99_LIMIT_MACRO_1790 1790
#define C99_LIMIT_MACRO_1791 1791
#define C99_LIMIT_MACRO_1792 1792
#define C99_LIMIT_MACRO_1793 1793
#define C99_LIMIT_MACRO_1794 1794
#define C99_LIMIT_MACRO_1795 1795
#define C99_LIMIT_MACRO_1796 1796
#define C99_LIMIT_MACRO_1797 1797
#define C99_LIMIT_MACRO_1798 1798
#define C99_LIMIT_MACRO_1799 1799
#define C99_LIMIT_MACRO_1800 1800
#define C99_LIMIT_MACRO_1801 1801
#define C99_LIMIT_MACRO_1802 1802
#define C99_LIMIT_MACRO_1803 1803
#define C99_LIMIT_MACRO_1804 1804
#define C99_LIMIT_MACRO_1805 1805
#define C99_LIMIT_MACRO_1806 1806
#define C99_LIMIT_MACRO_1807 1807
#define C99_LIMIT_MACRO_1808 1808
#define C99_LIMIT_MACRO_1809 1809
#define C99_LIMIT_MACRO_1810 1810
#define C99_LIMIT_MACRO_1811 1811
#define C99_LIMIT_MACRO_1812 1812
#define C99_LIMIT_MACRO_1813 1813
#define C99_LIMIT_MACRO_1814 1814
#define C99_LIMIT_MACRO_1815 1815
#define C99_LIMIT_MACRO_1816 1816
#define C99_LIMIT_MACRO_1817 1817
#define C99_LIMIT_MACRO_1818 1818
#define C99_LIMIT_MACRO_1819 1819
#define C99_LIMIT_MACRO_1820 1820
#define C99_LIMIT_MACRO_1821 1821
#define C99_LIMIT_MACRO_1822 1822
#define C99_LIMIT_MACRO_1823 1823
#define C99_LIMIT_MACRO_1824 1824
#define C99_LIMIT_MACRO_1825 1825
#define C99_LIMIT_MACRO_1826 1826
#define C99_LIMIT_MACRO_1827 1827
#define C99_LIMIT_MACRO_1828 1828
#define C99_LIMIT_MACRO_1829 1829
#define C99_LIMIT_MACRO_1830 1830
#define C99_LIMIT_MACRO_1831 1831
#define C99_LIMIT_MACRO_1832 1832
#define C99_LIMIT_MACRO_1833 1833
#define C99_LIMIT_MACRO_1834 1834
#define C99_LIMIT_MACRO_1835 1835
#define C99_LIMIT_MACRO_1836 1836
#define C99_LIMIT_MACRO_1837 1837
#define C99_LIMIT_MACRO_1838 1838
#define C99_LIMIT_MACRO_1839 1839
#define C99_LIMIT_MACRO_1840 1840
#define C99_LIMIT_MACRO_1841 1841
#define C99_LIMIT_MACRO_1842 1842
#define C99_LIMIT_MACRO_1843 1843
#define C99_LIMIT_MACRO_1844 1844
#define C99_LIMIT_MACRO_1845 1845
#define C99_LIMIT_MACRO_1846 1846
#define C99_LIMIT_MACRO_1847 1847
#define C99_LIMIT_MACRO_1848 1848
#define C99_LIMIT_MACRO_1849 1849
#define C99_LIMIT_MACRO_1850 1850
#define C99_LIMIT_MACRO_1851 1851
#define C99_LIMIT_MACRO_1852 1852
#define C99_LIMIT_MACRO_1853 1853
#define C99_LIMIT_MACRO_1854 1854
#define C99_LIMIT_MACRO_1855 1855
#define C99_LIMIT_MACRO_1856 1856
#define C99_LIMIT_MACRO_1857 1857
#define C99_LIMIT_MACRO_1858 1858
#define C99_LIMIT_MACRO_1859 1859
#define C99_LIMIT_MACRO_1860 1860
#define C99_LIMIT_MACRO_1861 1861
#define C99_LIMIT_MACRO_1862 1862
#define C99_LIMIT_MACRO_1863 1863
#define C99_LIMIT_MACRO_1864 1864
#define C99_LIMIT_MACRO_1865 1865
#define C99_LIMIT_MACRO_1866 1866
#define C99_LIMIT_MACRO_1867 1867
#define C99_LIMIT_MACRO_1868 1868
#define C99_LIMIT_MACRO_1869 1869
#define C99_LIMIT_MACRO_1870 1870
#define C99_LIMIT_MACRO_1871 1871
#define C99_LIMIT_MACRO_1872 1872
#define C99_LIMIT_MACRO_1873 1873
#define C99_LIMIT_MACRO_1874 1874
#define C99_LIMIT_MACRO_1875 1875
#define C99_LIMIT_MACRO_1876 1876
#define C99_LIMIT_MACRO_1877 1877
#define C99_LIMIT_MACRO_1878 1878
#define C99_LIMIT_MACRO_1879 1879
#define C99_LIMIT_MACRO_1880 1880
#define C99_LIMIT_MACRO_1881 1881
#define C99_LIMIT_MACRO_1882 1882
#define C99_LIMIT_MACRO_1883 1883
#define C99_LIMIT_MACRO_1884 1884
#define C99_LIMIT_MACRO_1885 1885
#define C99_LIMIT_MACRO_1886 1886
#define C99_LIMIT_MACRO_1887 1887
#define C99_LIMIT_MACRO_1888 1888
#define C99_LIMIT_MACRO_1889 1889
#define C99_LIMIT_MACRO_1890 1890
#define C99_LIMIT_MACRO_1891 1891
#define C99_LIMIT_MACRO_1892 1892
#define C99_LIMIT_MACRO_1893 1893
#define C99_LIMIT_MACRO_1894 1894
#define C99_LIMIT_MACRO_1895 1895
#define C99_LIMIT_MACRO_1896 1896
#define C99_LIMIT_MACRO_1897 1897
#define C99_LIMIT_MACRO_1898 1898
#define C99_LIMIT_MACRO_1899 1899
#define C99_LIMIT_MACRO_1900 1900
#define C99_LIMIT_MACRO_1901 1901
#define C99_LIMIT_MACRO_1902 1902
#define C99_LIMIT_MACRO_1903 1903
#define C99_LIMIT_MACRO_1904 1904
#define C99_LIMIT_MACRO_1905 1905
#define C99_LIMIT_MACRO_1906 1906
#define C99_LIMIT_MACRO_1907 1907
#define C99_LIMIT_MACRO_1908 1908
#define C99_LIMIT_MACRO_1909 1909
#define C99_LIMIT_MACRO_1910 1910
#define C99_LIMIT_MACRO_1911 1911
#define C99_LIMIT_MACRO_1912 1912
#define C99_LIMIT_MACRO_1913 1913
#define C99_LIMIT_MACRO_1914 1914
#define C99_LIMIT_MACRO_1915 1915
#define C99_LIMIT_MACRO_1916 1916
#define C99_LIMIT_MACRO_1917 1917
#define C99_LIMIT_MACRO_1918 1918
#define C99_LIMIT_MACRO_1919 1919
#define C99_LIMIT_MACRO_1920 1920
#define C99_LIMIT_MACRO_1921 1921
#define C99_LIMIT_MACRO_1922 1922
#define C99_LIMIT_MACRO_1923 1923
#define C99_LIMIT_MACRO_1924 1924
#define C99_LIMIT_MACRO_1925 1925
#define C99_LIMIT_MACRO_1926 1926
#define C99_LIMIT_MACRO_1927 1927
#define C99_LIMIT_MACRO_1928 1928
#define C99_LIMIT_MACRO_1929 1929
#define C99_LIMIT_MACRO_1930 1930
#define C99_LIMIT_MACRO_1931 1931
#define C99_LIMIT_MACRO_1932 1932
#define C99_LIMIT_MACRO_1933 1933
#define C99_LIMIT_MACRO_1934 1934
#define C99_LIMIT_MACRO_1935 1935
#define C99_LIMIT_MACRO_1936 1936
#define C99_LIMIT_MACRO_1937 1937
#define C99_LIMIT_MACRO_1938 1938
#define C99_LIMIT_MACRO_1939 1939
#define C99_LIMIT_MACRO_1940 1940
#define C99_LIMIT_MACRO_1941 1941
#define C99_LIMIT_MACRO_1942 1942
#define C99_LIMIT_MACRO_1943 1943
#define C99_LIMIT_MACRO_1944 1944
#define C99_LIMIT_MACRO_1945 1945
#define C99_LIMIT_MACRO_1946 1946
#define C99_LIMIT_MACRO_1947 1947
#define C99_LIMIT_MACRO_1948 1948
#define C99_LIMIT_MACRO_1949 1949
#define C99_LIMIT_MACRO_1950 1950
#define C99_LIMIT_MACRO_1951 1951
#define C99_LIMIT_MACRO_1952 1952
#define C99_LIMIT_MACRO_1953 1953
#define C99_LIMIT_MACRO_1954 1954
#define C99_LIMIT_MACRO_1955 1955
#define C99_LIMIT_MACRO_1956 1956
#define C99_LIMIT_MACRO_1957 1957
#define C99_LIMIT_MACRO_1958 1958
#define C99_LIMIT_MACRO_1959 1959
#define C99_LIMIT_MACRO_1960 1960
#define C99_LIMIT_MACRO_1961 1961
#define C99_LIMIT_MACRO_1962 1962
#define C99_LIMIT_MACRO_1963 1963
#define C99_LIMIT_MACRO_1964 1964
#define C99_LIMIT_MACRO_1965 1965
#define C99_LIMIT_MACRO_1966 1966
#define C99_LIMIT_MACRO_1967 1967
#define C99_LIMIT_MACRO_1968 1968
#define C99_LIMIT_MACRO_1969 1969
#define C99_LIMIT_MACRO_1970 1970
#define C99_LIMIT_MACRO_1971 1971
#define C99_LIMIT_MACRO_1972 1972
#define C99_LIMIT_MACRO_1973 1973
#define C99_LIMIT_MACRO_1974 1974
#define C99_LIMIT_MACRO_1975 1975
#define C99_LIMIT_MACRO_1976 1976
#define C99_LIMIT_MACRO_1977 1977
#define C99_LIMIT_MACRO_1978 1978
#define C99_LIMIT_MACRO_1979 1979
#define C99_LIMIT_MACRO_1980 1980
#define C99_LIMIT_MACRO_1981 1981
#define C99_LIMIT_MACRO_1982 1982
#define C99_LIMIT_MACRO_1983 1983
#define C99_LIMIT_MACRO_1984 1984
#define C99_LIMIT_MACRO_1985 1985
#define C99_LIMIT_MACRO_1986 1986
#define C99_LIMIT_MACRO_1987 1987
#define C99_LIMIT_MACRO_1988 1988
#define C99_LIMIT_MACRO_1989 1989
#define C99_LIMIT_MACRO_1990 1990
#define C99_LIMIT_MACRO_1991 1991
#define C99_LIMIT_MACRO_1992 1992
#define C99_LIMIT_MACRO_1993 1993
#define C99_LIMIT_MACRO_1994 1994
#define C99_LIMIT_MACRO_1995 1995
#define C99_LIMIT_MACRO_1996 1996
#define C99_LIMIT_MACRO_1997 1997
#define C99_LIMIT_MACRO_1998 1998
#define C99_LIMIT_MACRO_1999 1999
#define C99_LIMIT_MACRO_2000 2000
#define C99_LIMIT_MACRO_2001 2001
#define C99_LIMIT_MACRO_2002 2002
#define C99_LIMIT_MACRO_2003 2003
#define C99_LIMIT_MACRO_2004 2004
#define C99_LIMIT_MACRO_2005 2005
#define C99_LIMIT_MACRO_2006 2006
#define C99_LIMIT_MACRO_2007 2007
#define C99_LIMIT_MACRO_2008 2008
#define C99_LIMIT_MACRO_2009 2009
#define C99_LIMIT_MACRO_2010 2010
#define C99_LIMIT_MACRO_2011 2011
#define C99_LIMIT_MACRO_2012 2012
#define C99_LIMIT_MACRO_2013 2013
#define C99_LIMIT_MACRO_2014 2014
#define C99_LIMIT_MACRO_2015 2015
#define C99_LIMIT_MACRO_2016 2016
#define C99_LIMIT_MACRO_2017 2017
#define C99_LIMIT_MACRO_2018 2018
#define C99_LIMIT_MACRO_2019 2019
#define C99_LIMIT_MACRO_2020 2020
#define C99_LIMIT_MACRO_2021 2021
#define C99_LIMIT_MACRO_2022 2022
#define C99_LIMIT_MACRO_2023 2023
#define C99_LIMIT_MACRO_2024 2024
#define C99_LIMIT_MACRO_2025 2025
#define C99_LIMIT_MACRO_2026 2026
#define C99_LIMIT_MACRO_2027 2027
#define C99_LIMIT_MACRO_2028 2028
#define C99_LIMIT_MACRO_2029 2029
#define C99_LIMIT_MACRO_2030 2030
#define C99_LIMIT_MACRO_2031 2031
#define C99_LIMIT_MACRO_2032 2032
#define C99_LIMIT_MACRO_2033 2033
#define C99_LIMIT_MACRO_2034 2034
#define C99_LIMIT_MACRO_2035 2035
#define C99_LIMIT_MACRO_2036 2036
#define C99_LIMIT_MACRO_2037 2037
#define C99_LIMIT_MACRO_2038 2038
#define C99_LIMIT_MACRO_2039 2039
#define C99_LIMIT_MACRO_2040 2040
#define C99_LIMIT_MACRO_2041 2041
#define C99_LIMIT_MACRO_2042 2042
#define C99_LIMIT_MACRO_2043 2043
#define C99_LIMIT_MACRO_2044 2044
#define C99_LIMIT_MACRO_2045 2045
#define C99_LIMIT_MACRO_2046 2046
#define C99_LIMIT_MACRO_2047 2047
#define C99_LIMIT_MACRO_2048 2048
#define C99_LIMIT_MACRO_2049 2049
#define C99_LIMIT_MACRO_2050 2050
#define C99_LIMIT_MACRO_2051 2051
#define C99_LIMIT_MACRO_2052 2052
#define C99_LIMIT_MACRO_2053 2053
#define C99_LIMIT_MACRO_2054 2054
#define C99_LIMIT_MACRO_2055 2055
#define C99_LIMIT_MACRO_2056 2056
#define C99_LIMIT_MACRO_2057 2057
#define C99_LIMIT_MACRO_2058 2058
#define C99_LIMIT_MACRO_2059 2059
#define C99_LIMIT_MACRO_2060 2060
#define C99_LIMIT_MACRO_2061 2061
#define C99_LIMIT_MACRO_2062 2062
#define C99_LIMIT_MACRO_2063 2063
#define C99_LIMIT_MACRO_2064 2064
#define C99_LIMIT_MACRO_2065 2065
#define C99_LIMIT_MACRO_2066 2066
#define C99_LIMIT_MACRO_2067 2067
#define C99_LIMIT_MACRO_2068 2068
#define C99_LIMIT_MACRO_2069 2069
#define C99_LIMIT_MACRO_2070 2070
#define C99_LIMIT_MACRO_2071 2071
#define C99_LIMIT_MACRO_2072 2072
#define C99_LIMIT_MACRO_2073 2073
#define C99_LIMIT_MACRO_2074 2074
#define C99_LIMIT_MACRO_2075 2075
#define C99_LIMIT_MACRO_2076 2076
#define C99_LIMIT_MACRO_2077 2077
#define C99_LIMIT_MACRO_2078 2078
#define C99_LIMIT_MACRO_2079 2079
#define C99_LIMIT_MACRO_2080 2080
#define C99_LIMIT_MACRO_2081 2081
#define C99_LIMIT_MACRO_2082 2082
#define C99_LIMIT_MACRO_2083 2083
#define C99_LIMIT_MACRO_2084 2084
#define C99_LIMIT_MACRO_2085 2085
#define C99_LIMIT_MACRO_2086 2086
#define C99_LIMIT_MACRO_2087 2087
#define C99_LIMIT_MACRO_2088 2088
#define C99_LIMIT_MACRO_2089 2089
#define C99_LIMIT_MACRO_2090 2090
#define C99_LIMIT_MACRO_2091 2091
#define C99_LIMIT_MACRO_2092 2092
#define C99_LIMIT_MACRO_2093 2093
#define C99_LIMIT_MACRO_2094 2094
#define C99_LIMIT_MACRO_2095 2095
#define C99_LIMIT_MACRO_2096 2096
#define C99_LIMIT_MACRO_2097 2097
#define C99_LIMIT_MACRO_2098 2098
#define C99_LIMIT_MACRO_2099 2099
#define C99_LIMIT_MACRO_2100 2100
#define C99_LIMIT_MACRO_2101 2101
#define C99_LIMIT_MACRO_2102 2102
#define C99_LIMIT_MACRO_2103 2103
#define C99_LIMIT_MACRO_2104 2104
#define C99_LIMIT_MACRO_2105 2105
#define C99_LIMIT_MACRO_2106 2106
#define C99_LIMIT_MACRO_2107 2107
#define C99_LIMIT_MACRO_2108 2108
#define C99_LIMIT_MACRO_2109 2109
#define C99_LIMIT_MACRO_2110 2110
#define C99_LIMIT_MACRO_2111 2111
#define C99_LIMIT_MACRO_2112 2112
#define C99_LIMIT_MACRO_2113 2113
#define C99_LIMIT_MACRO_2114 2114
#define C99_LIMIT_MACRO_2115 2115
#define C99_LIMIT_MACRO_2116 2116
#define C99_LIMIT_MACRO_2117 2117
#define C99_LIMIT_MACRO_2118 2118
#define C99_LIMIT_MACRO_2119 2119
#define C99_LIMIT_MACRO_2120 2120
#define C99_LIMIT_MACRO_2121 2121
#define C99_LIMIT_MACRO_2122 2122
#define C99_LIMIT_MACRO_2123 2123
#define C99_LIMIT_MACRO_2124 2124
#define C99_LIMIT_MACRO_2125 2125
#define C99_LIMIT_MACRO_2126 2126
#define C99_LIMIT_MACRO_2127 2127
#define C99_LIMIT_MACRO_2128 2128
#define C99_LIMIT_MACRO_2129 2129
#define C99_LIMIT_MACRO_2130 2130
#define C99_LIMIT_MACRO_2131 2131
#define C99_LIMIT_MACRO_2132 2132
#define C99_LIMIT_MACRO_2133 2133
#define C99_LIMIT_MACRO_2134 2134
#define C99_LIMIT_MACRO_2135 2135
#define C99_LIMIT_MACRO_2136 2136
#define C99_LIMIT_MACRO_2137 2137
#define C99_LIMIT_MACRO_2138 2138
#define C99_LIMIT_MACRO_2139 2139
#define C99_LIMIT_MACRO_2140 2140
#define C99_LIMIT_MACRO_2141 2141
#define C99_LIMIT_MACRO_2142 2142
#define C99_LIMIT_MACRO_2143 2143
#define C99_LIMIT_MACRO_2144 2144
#define C99_LIMIT_MACRO_2145 2145
#define C99_LIMIT_MACRO_2146 2146
#define C99_LIMIT_MACRO_2147 2147
#define C99_LIMIT_MACRO_2148 2148
#define C99_LIMIT_MACRO_2149 2149
#define C99_LIMIT_MACRO_2150 2150
#define C99_LIMIT_MACRO_2151 2151
#define C99_LIMIT_MACRO_2152 2152
#define C99_LIMIT_MACRO_2153 2153
#define C99_LIMIT_MACRO_2154 2154
#define C99_LIMIT_MACRO_2155 2155
#define C99_LIMIT_MACRO_2156 2156
#define C99_LIMIT_MACRO_2157 2157
#define C99_LIMIT_MACRO_2158 2158
#define C99_LIMIT_MACRO_2159 2159
#define C99_LIMIT_MACRO_2160 2160
#define C99_LIMIT_MACRO_2161 2161
#define C99_LIMIT_MACRO_2162 2162
#define C99_LIMIT_MACRO_2163 2163
#define C99_LIMIT_MACRO_2164 2164
#define C99_LIMIT_MACRO_2165 2165
#define C99_LIMIT_MACRO_2166 2166
#define C99_LIMIT_MACRO_2167 2167
#define C99_LIMIT_MACRO_2168 2168
#define C99_LIMIT_MACRO_2169 2169
#define C99_LIMIT_MACRO_2170 2170
#define C99_LIMIT_MACRO_2171 2171
#define C99_LIMIT_MACRO_2172 2172
#define C99_LIMIT_MACRO_2173 2173
#define C99_LIMIT_MACRO_2174 2174
#define C99_LIMIT_MACRO_2175 2175
#define C99_LIMIT_MACRO_2176 2176
#define C99_LIMIT_MACRO_2177 2177
#define C99_LIMIT_MACRO_2178 2178
#define C99_LIMIT_MACRO_2179 2179
#define C99_LIMIT_MACRO_2180 2180
#define C99_LIMIT_MACRO_2181 2181
#define C99_LIMIT_MACRO_2182 2182
#define C99_LIMIT_MACRO_2183 2183
#define C99_LIMIT_MACRO_2184 2184
#define C99_LIMIT_MACRO_2185 2185
#define C99_LIMIT_MACRO_2186 2186
#define C99_LIMIT_MACRO_2187 2187
#define C99_LIMIT_MACRO_2188 2188
#define C99_LIMIT_MACRO_2189 2189
#define C99_LIMIT_MACRO_2190 2190
#define C99_LIMIT_MACRO_2191 2191
#define C99_LIMIT_MACRO_2192 2192
#define C99_LIMIT_MACRO_2193 2193
#define C99_LIMIT_MACRO_2194 2194
#define C99_LIMIT_MACRO_2195 2195
#define C99_LIMIT_MACRO_2196 2196
#define C99_LIMIT_MACRO_2197 2197
#define C99_LIMIT_MACRO_2198 2198
#define C99_LIMIT_MACRO_2199 2199
#define C99_LIMIT_MACRO_2200 2200
#define C99_LIMIT_MACRO_2201 2201
#define C99_LIMIT_MACRO_2202 2202
#define C99_LIMIT_MACRO_2203 2203
#define C99_LIMIT_MACRO_2204 2204
#define C99_LIMIT_MACRO_2205 2205
#define C99_LIMIT_MACRO_2206 2206
#define C99_LIMIT_MACRO_2207 2207
#define C99_LIMIT_MACRO_2208 2208
#define C99_LIMIT_MACRO_2209 2209
#define C99_LIMIT_MACRO_2210 2210
#define C99_LIMIT_MACRO_2211 2211
#define C99_LIMIT_MACRO_2212 2212
#define C99_LIMIT_MACRO_2213 2213
#define C99_LIMIT_MACRO_2214 2214
#define C99_LIMIT_MACRO_2215 2215
#define C99_LIMIT_MACRO_2216 2216
#define C99_LIMIT_MACRO_2217 2217
#define C99_LIMIT_MACRO_2218 2218
#define C99_LIMIT_MACRO_2219 2219
#define C99_LIMIT_MACRO_2220 2220
#define C99_LIMIT_MACRO_2221 2221
#define C99_LIMIT_MACRO_2222 2222
#define C99_LIMIT_MACRO_2223 2223
#define C99_LIMIT_MACRO_2224 2224
#define C99_LIMIT_MACRO_2225 2225
#define C99_LIMIT_MACRO_2226 2226
#define C99_LIMIT_MACRO_2227 2227
#define C99_LIMIT_MACRO_2228 2228
#define C99_LIMIT_MACRO_2229 2229
#define C99_LIMIT_MACRO_2230 2230
#define C99_LIMIT_MACRO_2231 2231
#define C99_LIMIT_MACRO_2232 2232
#define C99_LIMIT_MACRO_2233 2233
#define C99_LIMIT_MACRO_2234 2234
#define C99_LIMIT_MACRO_2235 2235
#define C99_LIMIT_MACRO_2236 2236
#define C99_LIMIT_MACRO_2237 2237
#define C99_LIMIT_MACRO_2238 2238
#define C99_LIMIT_MACRO_2239 2239
#define C99_LIMIT_MACRO_2240 2240
#define C99_LIMIT_MACRO_2241 2241
#define C99_LIMIT_MACRO_2242 2242
#define C99_LIMIT_MACRO_2243 2243
#define C99_LIMIT_MACRO_2244 2244
#define C99_LIMIT_MACRO_2245 2245
#define C99_LIMIT_MACRO_2246 2246
#define C99_LIMIT_MACRO_2247 2247
#define C99_LIMIT_MACRO_2248 2248
#define C99_LIMIT_MACRO_2249 2249
#define C99_LIMIT_MACRO_2250 2250
#define C99_LIMIT_MACRO_2251 2251
#define C99_LIMIT_MACRO_2252 2252
#define C99_LIMIT_MACRO_2253 2253
#define C99_LIMIT_MACRO_2254 2254
#define C99_LIMIT_MACRO_2255 2255
#define C99_LIMIT_MACRO_2256 2256
#define C99_LIMIT_MACRO_2257 2257
#define C99_LIMIT_MACRO_2258 2258
#define C99_LIMIT_MACRO_2259 2259
#define C99_LIMIT_MACRO_2260 2260
#define C99_LIMIT_MACRO_2261 2261
#define C99_LIMIT_MACRO_2262 2262
#define C99_LIMIT_MACRO_2263 2263
#define C99_LIMIT_MACRO_2264 2264
#define C99_LIMIT_MACRO_2265 2265
#define C99_LIMIT_MACRO_2266 2266
#define C99_LIMIT_MACRO_2267 2267
#define C99_LIMIT_MACRO_2268 2268
#define C99_LIMIT_MACRO_2269 2269
#define C99_LIMIT_MACRO_2270 2270
#define C99_LIMIT_MACRO_2271 2271
#define C99_LIMIT_MACRO_2272 2272
#define C99_LIMIT_MACRO_2273 2273
#define C99_LIMIT_MACRO_2274 2274
#define C99_LIMIT_MACRO_2275 2275
#define C99_LIMIT_MACRO_2276 2276
#define C99_LIMIT_MACRO_2277 2277
#define C99_LIMIT_MACRO_2278 2278
#define C99_LIMIT_MACRO_2279 2279
#define C99_LIMIT_MACRO_2280 2280
#define C99_LIMIT_MACRO_2281 2281
#define C99_LIMIT_MACRO_2282 2282
#define C99_LIMIT_MACRO_2283 2283
#define C99_LIMIT_MACRO_2284 2284
#define C99_LIMIT_MACRO_2285 2285
#define C99_LIMIT_MACRO_2286 2286
#define C99_LIMIT_MACRO_2287 2287
#define C99_LIMIT_MACRO_2288 2288
#define C99_LIMIT_MACRO_2289 2289
#define C99_LIMIT_MACRO_2290 2290
#define C99_LIMIT_MACRO_2291 2291
#define C99_LIMIT_MACRO_2292 2292
#define C99_LIMIT_MACRO_2293 2293
#define C99_LIMIT_MACRO_2294 2294
#define C99_LIMIT_MACRO_2295 2295
#define C99_LIMIT_MACRO_2296 2296
#define C99_LIMIT_MACRO_2297 2297
#define C99_LIMIT_MACRO_2298 2298
#define C99_LIMIT_MACRO_2299 2299
#define C99_LIMIT_MACRO_2300 2300
#define C99_LIMIT_MACRO_2301 2301
#define C99_LIMIT_MACRO_2302 2302
#define C99_LIMIT_MACRO_2303 2303
#define C99_LIMIT_MACRO_2304 2304
#define C99_LIMIT_MACRO_2305 2305
#define C99_LIMIT_MACRO_2306 2306
#define C99_LIMIT_MACRO_2307 2307
#define C99_LIMIT_MACRO_2308 2308
#define C99_LIMIT_MACRO_2309 2309
#define C99_LIMIT_MACRO_2310 2310
#define C99_LIMIT_MACRO_2311 2311
#define C99_LIMIT_MACRO_2312 2312
#define C99_LIMIT_MACRO_2313 2313
#define C99_LIMIT_MACRO_2314 2314
#define C99_LIMIT_MACRO_2315 2315
#define C99_LIMIT_MACRO_2316 2316
#define C99_LIMIT_MACRO_2317 2317
#define C99_LIMIT_MACRO_2318 2318
#define C99_LIMIT_MACRO_2319 2319
#define C99_LIMIT_MACRO_2320 2320
#define C99_LIMIT_MACRO_2321 2321
#define C99_LIMIT_MACRO_2322 2322
#define C99_LIMIT_MACRO_2323 2323
#define C99_LIMIT_MACRO_2324 2324
#define C99_LIMIT_MACRO_2325 2325
#define C99_LIMIT_MACRO_2326 2326
#define C99_LIMIT_MACRO_2327 2327
#define C99_LIMIT_MACRO_2328 2328
#define C99_LIMIT_MACRO_2329 2329
#define C99_LIMIT_MACRO_2330 2330
#define C99_LIMIT_MACRO_2331 2331
#define C99_LIMIT_MACRO_2332 2332
#define C99_LIMIT_MACRO_2333 2333
#define C99_LIMIT_MACRO_2334 2334
#define C99_LIMIT_MACRO_2335 2335
#define C99_LIMIT_MACRO_2336 2336
#define C99_LIMIT_MACRO_2337 2337
#define C99_LIMIT_MACRO_2338 2338
#define C99_LIMIT_MACRO_2339 2339
#define C99_LIMIT_MACRO_2340 2340
#define C99_LIMIT_MACRO_2341 2341
#define C99_LIMIT_MACRO_2342 2342
#define C99_LIMIT_MACRO_2343 2343
#define C99_LIMIT_MACRO_2344 2344
#define C99_LIMIT_MACRO_2345 2345
#define C99_LIMIT_MACRO_2346 2346
#define C99_LIMIT_MACRO_2347 2347
#define C99_LIMIT_MACRO_2348 2348
#define C99_LIMIT_MACRO_2349 2349
#define C99_LIMIT_MACRO_2350 2350
#define C99_LIMIT_MACRO_2351 2351
#define C99_LIMIT_MACRO_2352 2352
#define C99_LIMIT_MACRO_2353 2353
#define C99_LIMIT_MACRO_2354 2354
#define C99_LIMIT_MACRO_2355 2355
#define C99_LIMIT_MACRO_2356 2356
#define C99_LIMIT_MACRO_2357 2357
#define C99_LIMIT_MACRO_2358 2358
#define C99_LIMIT_MACRO_2359 2359
#define C99_LIMIT_MACRO_2360 2360
#define C99_LIMIT_MACRO_2361 2361
#define C99_LIMIT_MACRO_2362 2362
#define C99_LIMIT_MACRO_2363 2363
#define C99_LIMIT_MACRO_2364 2364
#define C99_LIMIT_MACRO_2365 2365
#define C99_LIMIT_MACRO_2366 2366
#define C99_LIMIT_MACRO_2367 2367
#define C99_LIMIT_MACRO_2368 2368
#define C99_LIMIT_MACRO_2369 2369
#define C99_LIMIT_MACRO_2370 2370
#define C99_LIMIT_MACRO_2371 2371
#define C99_LIMIT_MACRO_2372 2372
#define C99_LIMIT_MACRO_2373 2373
#define C99_LIMIT_MACRO_2374 2374
#define C99_LIMIT_MACRO_2375 2375
#define C99_LIMIT_MACRO_2376 2376
#define C99_LIMIT_MACRO_2377 2377
#define C99_LIMIT_MACRO_2378 2378
#define C99_LIMIT_MACRO_2379 2379
#define C99_LIMIT_MACRO_2380 2380
#define C99_LIMIT_MACRO_2381 2381
#define C99_LIMIT_MACRO_2382 2382
#define C99_LIMIT_MACRO_2383 2383
#define C99_LIMIT_MACRO_2384 2384
#define C99_LIMIT_MACRO_2385 2385
#define C99_LIMIT_MACRO_2386 2386
#define C99_LIMIT_MACRO_2387 2387
#define C99_LIMIT_MACRO_2388 2388
#define C99_LIMIT_MACRO_2389 2389
#define C99_LIMIT_MACRO_2390 2390
#define C99_LIMIT_MACRO_2391 2391
#define C99_LIMIT_MACRO_2392 2392
#define C99_LIMIT_MACRO_2393 2393
#define C99_LIMIT_MACRO_2394 2394
#define C99_LIMIT_MACRO_2395 2395
#define C99_LIMIT_MACRO_2396 2396
#define C99_LIMIT_MACRO_2397 2397
#define C99_LIMIT_MACRO_2398 2398
#define C99_LIMIT_MACRO_2399 2399
#define C99_LIMIT_MACRO_2400 2400
#define C99_LIMIT_MACRO_2401 2401
#define C99_LIMIT_MACRO_2402 2402
#define C99_LIMIT_MACRO_2403 2403
#define C99_LIMIT_MACRO_2404 2404
#define C99_LIMIT_MACRO_2405 2405
#define C99_LIMIT_MACRO_2406 2406
#define C99_LIMIT_MACRO_2407 2407
#define C99_LIMIT_MACRO_2408 2408
#define C99_LIMIT_MACRO_2409 2409
#define C99_LIMIT_MACRO_2410 2410
#define C99_LIMIT_MACRO_2411 2411
#define C99_LIMIT_MACRO_2412 2412
#define C99_LIMIT_MACRO_2413 2413
#define C99_LIMIT_MACRO_2414 2414
#define C99_LIMIT_MACRO_2415 2415
#define C99_LIMIT_MACRO_2416 2416
#define C99_LIMIT_MACRO_2417 2417
#define C99_LIMIT_MACRO_2418 2418
#define C99_LIMIT_MACRO_2419 2419
#define C99_LIMIT_MACRO_2420 2420
#define C99_LIMIT_MACRO_2421 2421
#define C99_LIMIT_MACRO_2422 2422
#define C99_LIMIT_MACRO_2423 2423
#define C99_LIMIT_MACRO_2424 2424
#define C99_LIMIT_MACRO_2425 2425
#define C99_LIMIT_MACRO_2426 2426
#define C99_LIMIT_MACRO_2427 2427
#define C99_LIMIT_MACRO_2428 2428
#define C99_LIMIT_MACRO_2429 2429
#define C99_LIMIT_MACRO_2430 2430
#define C99_LIMIT_MACRO_2431 2431
#define C99_LIMIT_MACRO_2432 2432
#define C99_LIMIT_MACRO_2433 2433
#define C99_LIMIT_MACRO_2434 2434
#define C99_LIMIT_MACRO_2435 2435
#define C99_LIMIT_MACRO_2436 2436
#define C99_LIMIT_MACRO_2437 2437
#define C99_LIMIT_MACRO_2438 2438
#define C99_LIMIT_MACRO_2439 2439
#define C99_LIMIT_MACRO_2440 2440
#define C99_LIMIT_MACRO_2441 2441
#define C99_LIMIT_MACRO_2442 2442
#define C99_LIMIT_MACRO_2443 2443
#define C99_LIMIT_MACRO_2444 2444
#define C99_LIMIT_MACRO_2445 2445
#define C99_LIMIT_MACRO_2446 2446
#define C99_LIMIT_MACRO_2447 2447
#define C99_LIMIT_MACRO_2448 2448
#define C99_LIMIT_MACRO_2449 2449
#define C99_LIMIT_MACRO_2450 2450
#define C99_LIMIT_MACRO_2451 2451
#define C99_LIMIT_MACRO_2452 2452
#define C99_LIMIT_MACRO_2453 2453
#define C99_LIMIT_MACRO_2454 2454
#define C99_LIMIT_MACRO_2455 2455
#define C99_LIMIT_MACRO_2456 2456
#define C99_LIMIT_MACRO_2457 2457
#define C99_LIMIT_MACRO_2458 2458
#define C99_LIMIT_MACRO_2459 2459
#define C99_LIMIT_MACRO_2460 2460
#define C99_LIMIT_MACRO_2461 2461
#define C99_LIMIT_MACRO_2462 2462
#define C99_LIMIT_MACRO_2463 2463
#define C99_LIMIT_MACRO_2464 2464
#define C99_LIMIT_MACRO_2465 2465
#define C99_LIMIT_MACRO_2466 2466
#define C99_LIMIT_MACRO_2467 2467
#define C99_LIMIT_MACRO_2468 2468
#define C99_LIMIT_MACRO_2469 2469
#define C99_LIMIT_MACRO_2470 2470
#define C99_LIMIT_MACRO_2471 2471
#define C99_LIMIT_MACRO_2472 2472
#define C99_LIMIT_MACRO_2473 2473
#define C99_LIMIT_MACRO_2474 2474
#define C99_LIMIT_MACRO_2475 2475
#define C99_LIMIT_MACRO_2476 2476
#define C99_LIMIT_MACRO_2477 2477
#define C99_LIMIT_MACRO_2478 2478
#define C99_LIMIT_MACRO_2479 2479
#define C99_LIMIT_MACRO_2480 2480
#define C99_LIMIT_MACRO_2481 2481
#define C99_LIMIT_MACRO_2482 2482
#define C99_LIMIT_MACRO_2483 2483
#define C99_LIMIT_MACRO_2484 2484
#define C99_LIMIT_MACRO_2485 2485
#define C99_LIMIT_MACRO_2486 2486
#define C99_LIMIT_MACRO_2487 2487
#define C99_LIMIT_MACRO_2488 2488
#define C99_LIMIT_MACRO_2489 2489
#define C99_LIMIT_MACRO_2490 2490
#define C99_LIMIT_MACRO_2491 2491
#define C99_LIMIT_MACRO_2492 2492
#define C99_LIMIT_MACRO_2493 2493
#define C99_LIMIT_MACRO_2494 2494
#define C99_LIMIT_MACRO_2495 2495
#define C99_LIMIT_MACRO_2496 2496
#define C99_LIMIT_MACRO_2497 2497
#define C99_LIMIT_MACRO_2498 2498
#define C99_LIMIT_MACRO_2499 2499
#define C99_LIMIT_MACRO_2500 2500
#define C99_LIMIT_MACRO_2501 2501
#define C99_LIMIT_MACRO_2502 2502
#define C99_LIMIT_MACRO_2503 2503
#define C99_LIMIT_MACRO_2504 2504
#define C99_LIMIT_MACRO_2505 2505
#define C99_LIMIT_MACRO_2506 2506
#define C99_LIMIT_MACRO_2507 2507
#define C99_LIMIT_MACRO_2508 2508
#define C99_LIMIT_MACRO_2509 2509
#define C99_LIMIT_MACRO_2510 2510
#define C99_LIMIT_MACRO_2511 2511
#define C99_LIMIT_MACRO_2512 2512
#define C99_LIMIT_MACRO_2513 2513
#define C99_LIMIT_MACRO_2514 2514
#define C99_LIMIT_MACRO_2515 2515
#define C99_LIMIT_MACRO_2516 2516
#define C99_LIMIT_MACRO_2517 2517
#define C99_LIMIT_MACRO_2518 2518
#define C99_LIMIT_MACRO_2519 2519
#define C99_LIMIT_MACRO_2520 2520
#define C99_LIMIT_MACRO_2521 2521
#define C99_LIMIT_MACRO_2522 2522
#define C99_LIMIT_MACRO_2523 2523
#define C99_LIMIT_MACRO_2524 2524
#define C99_LIMIT_MACRO_2525 2525
#define C99_LIMIT_MACRO_2526 2526
#define C99_LIMIT_MACRO_2527 2527
#define C99_LIMIT_MACRO_2528 2528
#define C99_LIMIT_MACRO_2529 2529
#define C99_LIMIT_MACRO_2530 2530
#define C99_LIMIT_MACRO_2531 2531
#define C99_LIMIT_MACRO_2532 2532
#define C99_LIMIT_MACRO_2533 2533
#define C99_LIMIT_MACRO_2534 2534
#define C99_LIMIT_MACRO_2535 2535
#define C99_LIMIT_MACRO_2536 2536
#define C99_LIMIT_MACRO_2537 2537
#define C99_LIMIT_MACRO_2538 2538
#define C99_LIMIT_MACRO_2539 2539
#define C99_LIMIT_MACRO_2540 2540
#define C99_LIMIT_MACRO_2541 2541
#define C99_LIMIT_MACRO_2542 2542
#define C99_LIMIT_MACRO_2543 2543
#define C99_LIMIT_MACRO_2544 2544
#define C99_LIMIT_MACRO_2545 2545
#define C99_LIMIT_MACRO_2546 2546
#define C99_LIMIT_MACRO_2547 2547
#define C99_LIMIT_MACRO_2548 2548
#define C99_LIMIT_MACRO_2549 2549
#define C99_LIMIT_MACRO_2550 2550
#define C99_LIMIT_MACRO_2551 2551
#define C99_LIMIT_MACRO_2552 2552
#define C99_LIMIT_MACRO_2553 2553
#define C99_LIMIT_MACRO_2554 2554
#define C99_LIMIT_MACRO_2555 2555
#define C99_LIMIT_MACRO_2556 2556
#define C99_LIMIT_MACRO_2557 2557
#define C99_LIMIT_MACRO_2558 2558
#define C99_LIMIT_MACRO_2559 2559
#define C99_LIMIT_MACRO_2560 2560
#define C99_LIMIT_MACRO_2561 2561
#define C99_LIMIT_MACRO_2562 2562
#define C99_LIMIT_MACRO_2563 2563
#define C99_LIMIT_MACRO_2564 2564
#define C99_LIMIT_MACRO_2565 2565
#define C99_LIMIT_MACRO_2566 2566
#define C99_LIMIT_MACRO_2567 2567
#define C99_LIMIT_MACRO_2568 2568
#define C99_LIMIT_MACRO_2569 2569
#define C99_LIMIT_MACRO_2570 2570
#define C99_LIMIT_MACRO_2571 2571
#define C99_LIMIT_MACRO_2572 2572
#define C99_LIMIT_MACRO_2573 2573
#define C99_LIMIT_MACRO_2574 2574
#define C99_LIMIT_MACRO_2575 2575
#define C99_LIMIT_MACRO_2576 2576
#define C99_LIMIT_MACRO_2577 2577
#define C99_LIMIT_MACRO_2578 2578
#define C99_LIMIT_MACRO_2579 2579
#define C99_LIMIT_MACRO_2580 2580
#define C99_LIMIT_MACRO_2581 2581
#define C99_LIMIT_MACRO_2582 2582
#define C99_LIMIT_MACRO_2583 2583
#define C99_LIMIT_MACRO_2584 2584
#define C99_LIMIT_MACRO_2585 2585
#define C99_LIMIT_MACRO_2586 2586
#define C99_LIMIT_MACRO_2587 2587
#define C99_LIMIT_MACRO_2588 2588
#define C99_LIMIT_MACRO_2589 2589
#define C99_LIMIT_MACRO_2590 2590
#define C99_LIMIT_MACRO_2591 2591
#define C99_LIMIT_MACRO_2592 2592
#define C99_LIMIT_MACRO_2593 2593
#define C99_LIMIT_MACRO_2594 2594
#define C99_LIMIT_MACRO_2595 2595
#define C99_LIMIT_MACRO_2596 2596
#define C99_LIMIT_MACRO_2597 2597
#define C99_LIMIT_MACRO_2598 2598
#define C99_LIMIT_MACRO_2599 2599
#define C99_LIMIT_MACRO_2600 2600
#define C99_LIMIT_MACRO_2601 2601
#define C99_LIMIT_MACRO_2602 2602
#define C99_LIMIT_MACRO_2603 2603
#define C99_LIMIT_MACRO_2604 2604
#define C99_LIMIT_MACRO_2605 2605
#define C99_LIMIT_MACRO_2606 2606
#define C99_LIMIT_MACRO_2607 2607
#define C99_LIMIT_MACRO_2608 2608
#define C99_LIMIT_MACRO_2609 2609
#define C99_LIMIT_MACRO_2610 2610
#define C99_LIMIT_MACRO_2611 2611
#define C99_LIMIT_MACRO_2612 2612
#define C99_LIMIT_MACRO_2613 2613
#define C99_LIMIT_MACRO_2614 2614
#define C99_LIMIT_MACRO_2615 2615
#define C99_LIMIT_MACRO_2616 2616
#define C99_LIMIT_MACRO_2617 2617
#define C99_LIMIT_MACRO_2618 2618
#define C99_LIMIT_MACRO_2619 2619
#define C99_LIMIT_MACRO_2620 2620
#define C99_LIMIT_MACRO_2621 2621
#define C99_LIMIT_MACRO_2622 2622
#define C99_LIMIT_MACRO_2623 2623
#define C99_LIMIT_MACRO_2624 2624
#define C99_LIMIT_MACRO_2625 2625
#define C99_LIMIT_MACRO_2626 2626
#define C99_LIMIT_MACRO_2627 2627
#define C99_LIMIT_MACRO_2628 2628
#define C99_LIMIT_MACRO_2629 2629
#define C99_LIMIT_MACRO_2630 2630
#define C99_LIMIT_MACRO_2631 2631
#define C99_LIMIT_MACRO_2632 2632
#define C99_LIMIT_MACRO_2633 2633
#define C99_LIMIT_MACRO_2634 2634
#define C99_LIMIT_MACRO_2635 2635
#define C99_LIMIT_MACRO_2636 2636
#define C99_LIMIT_MACRO_2637 2637
#define C99_LIMIT_MACRO_2638 2638
#define C99_LIMIT_MACRO_2639 2639
#define C99_LIMIT_MACRO_2640 2640
#define C99_LIMIT_MACRO_2641 2641
#define C99_LIMIT_MACRO_2642 2642
#define C99_LIMIT_MACRO_2643 2643
#define C99_LIMIT_MACRO_2644 2644
#define C99_LIMIT_MACRO_2645 2645
#define C99_LIMIT_MACRO_2646 2646
#define C99_LIMIT_MACRO_2647 2647
#define C99_LIMIT_MACRO_2648 2648
#define C99_LIMIT_MACRO_2649 2649
#define C99_LIMIT_MACRO_2650 2650
#define C99_LIMIT_MACRO_2651 2651
#define C99_LIMIT_MACRO_2652 2652
#define C99_LIMIT_MACRO_2653 2653
#define C99_LIMIT_MACRO_2654 2654
#define C99_LIMIT_MACRO_2655 2655
#define C99_LIMIT_MACRO_2656 2656
#define C99_LIMIT_MACRO_2657 2657
#define C99_LIMIT_MACRO_2658 2658
#define C99_LIMIT_MACRO_2659 2659
#define C99_LIMIT_MACRO_2660 2660
#define C99_LIMIT_MACRO_2661 2661
#define C99_LIMIT_MACRO_2662 2662
#define C99_LIMIT_MACRO_2663 2663
#define C99_LIMIT_MACRO_2664 2664
#define C99_LIMIT_MACRO_2665 2665
#define C99_LIMIT_MACRO_2666 2666
#define C99_LIMIT_MACRO_2667 2667
#define C99_LIMIT_MACRO_2668 2668
#define C99_LIMIT_MACRO_2669 2669
#define C99_LIMIT_MACRO_2670 2670
#define C99_LIMIT_MACRO_2671 2671
#define C99_LIMIT_MACRO_2672 2672
#define C99_LIMIT_MACRO_2673 2673
#define C99_LIMIT_MACRO_2674 2674
#define C99_LIMIT_MACRO_2675 2675
#define C99_LIMIT_MACRO_2676 2676
#define C99_LIMIT_MACRO_2677 2677
#define C99_LIMIT_MACRO_2678 2678
#define C99_LIMIT_MACRO_2679 2679
#define C99_LIMIT_MACRO_2680 2680
#define C99_LIMIT_MACRO_2681 2681
#define C99_LIMIT_MACRO_2682 2682
#define C99_LIMIT_MACRO_2683 2683
#define C99_LIMIT_MACRO_2684 2684
#define C99_LIMIT_MACRO_2685 2685
#define C99_LIMIT_MACRO_2686 2686
#define C99_LIMIT_MACRO_2687 2687
#define C99_LIMIT_MACRO_2688 2688
#define C99_LIMIT_MACRO_2689 2689
#define C99_LIMIT_MACRO_2690 2690
#define C99_LIMIT_MACRO_2691 2691
#define C99_LIMIT_MACRO_2692 2692
#define C99_LIMIT_MACRO_2693 2693
#define C99_LIMIT_MACRO_2694 2694
#define C99_LIMIT_MACRO_2695 2695
#define C99_LIMIT_MACRO_2696 2696
#define C99_LIMIT_MACRO_2697 2697
#define C99_LIMIT_MACRO_2698 2698
#define C99_LIMIT_MACRO_2699 2699
#define C99_LIMIT_MACRO_2700 2700
#define C99_LIMIT_MACRO_2701 2701
#define C99_LIMIT_MACRO_2702 2702
#define C99_LIMIT_MACRO_2703 2703
#define C99_LIMIT_MACRO_2704 2704
#define C99_LIMIT_MACRO_2705 2705
#define C99_LIMIT_MACRO_2706 2706
#define C99_LIMIT_MACRO_2707 2707
#define C99_LIMIT_MACRO_2708 2708
#define C99_LIMIT_MACRO_2709 2709
#define C99_LIMIT_MACRO_2710 2710
#define C99_LIMIT_MACRO_2711 2711
#define C99_LIMIT_MACRO_2712 2712
#define C99_LIMIT_MACRO_2713 2713
#define C99_LIMIT_MACRO_2714 2714
#define C99_LIMIT_MACRO_2715 2715
#define C99_LIMIT_MACRO_2716 2716
#define C99_LIMIT_MACRO_2717 2717
#define C99_LIMIT_MACRO_2718 2718
#define C99_LIMIT_MACRO_2719 2719
#define C99_LIMIT_MACRO_2720 2720
#define C99_LIMIT_MACRO_2721 2721
#define C99_LIMIT_MACRO_2722 2722
#define C99_LIMIT_MACRO_2723 2723
#define C99_LIMIT_MACRO_2724 2724
#define C99_LIMIT_MACRO_2725 2725
#define C99_LIMIT_MACRO_2726 2726
#define C99_LIMIT_MACRO_2727 2727
#define C99_LIMIT_MACRO_2728 2728
#define C99_LIMIT_MACRO_2729 2729
#define C99_LIMIT_MACRO_2730 2730
#define C99_LIMIT_MACRO_2731 2731
#define C99_LIMIT_MACRO_2732 2732
#define C99_LIMIT_MACRO_2733 2733
#define C99_LIMIT_MACRO_2734 2734
#define C99_LIMIT_MACRO_2735 2735
#define C99_LIMIT_MACRO_2736 2736
#define C99_LIMIT_MACRO_2737 2737
#define C99_LIMIT_MACRO_2738 2738
#define C99_LIMIT_MACRO_2739 2739
#define C99_LIMIT_MACRO_2740 2740
#define C99_LIMIT_MACRO_2741 2741
#define C99_LIMIT_MACRO_2742 2742
#define C99_LIMIT_MACRO_2743 2743
#define C99_LIMIT_MACRO_2744 2744
#define C99_LIMIT_MACRO_2745 2745
#define C99_LIMIT_MACRO_2746 2746
#define C99_LIMIT_MACRO_2747 2747
#define C99_LIMIT_MACRO_2748 2748
#define C99_LIMIT_MACRO_2749 2749
#define C99_LIMIT_MACRO_2750 2750
#define C99_LIMIT_MACRO_2751 2751
#define C99_LIMIT_MACRO_2752 2752
#define C99_LIMIT_MACRO_2753 2753
#define C99_LIMIT_MACRO_2754 2754
#define C99_LIMIT_MACRO_2755 2755
#define C99_LIMIT_MACRO_2756 2756
#define C99_LIMIT_MACRO_2757 2757
#define C99_LIMIT_MACRO_2758 2758
#define C99_LIMIT_MACRO_2759 2759
#define C99_LIMIT_MACRO_2760 2760
#define C99_LIMIT_MACRO_2761 2761
#define C99_LIMIT_MACRO_2762 2762
#define C99_LIMIT_MACRO_2763 2763
#define C99_LIMIT_MACRO_2764 2764
#define C99_LIMIT_MACRO_2765 2765
#define C99_LIMIT_MACRO_2766 2766
#define C99_LIMIT_MACRO_2767 2767
#define C99_LIMIT_MACRO_2768 2768
#define C99_LIMIT_MACRO_2769 2769
#define C99_LIMIT_MACRO_2770 2770
#define C99_LIMIT_MACRO_2771 2771
#define C99_LIMIT_MACRO_2772 2772
#define C99_LIMIT_MACRO_2773 2773
#define C99_LIMIT_MACRO_2774 2774
#define C99_LIMIT_MACRO_2775 2775
#define C99_LIMIT_MACRO_2776 2776
#define C99_LIMIT_MACRO_2777 2777
#define C99_LIMIT_MACRO_2778 2778
#define C99_LIMIT_MACRO_2779 2779
#define C99_LIMIT_MACRO_2780 2780
#define C99_LIMIT_MACRO_2781 2781
#define C99_LIMIT_MACRO_2782 2782
#define C99_LIMIT_MACRO_2783 2783
#define C99_LIMIT_MACRO_2784 2784
#define C99_LIMIT_MACRO_2785 2785
#define C99_LIMIT_MACRO_2786 2786
#define C99_LIMIT_MACRO_2787 2787
#define C99_LIMIT_MACRO_2788 2788
#define C99_LIMIT_MACRO_2789 2789
#define C99_LIMIT_MACRO_2790 2790
#define C99_LIMIT_MACRO_2791 2791
#define C99_LIMIT_MACRO_2792 2792
#define C99_LIMIT_MACRO_2793 2793
#define C99_LIMIT_MACRO_2794 2794
#define C99_LIMIT_MACRO_2795 2795
#define C99_LIMIT_MACRO_2796 2796
#define C99_LIMIT_MACRO_2797 2797
#define C99_LIMIT_MACRO_2798 2798
#define C99_LIMIT_MACRO_2799 2799
#define C99_LIMIT_MACRO_2800 2800
#define C99_LIMIT_MACRO_2801 2801
#define C99_LIMIT_MACRO_2802 2802
#define C99_LIMIT_MACRO_2803 2803
#define C99_LIMIT_MACRO_2804 2804
#define C99_LIMIT_MACRO_2805 2805
#define C99_LIMIT_MACRO_2806 2806
#define C99_LIMIT_MACRO_2807 2807
#define C99_LIMIT_MACRO_2808 2808
#define C99_LIMIT_MACRO_2809 2809
#define C99_LIMIT_MACRO_2810 2810
#define C99_LIMIT_MACRO_2811 2811
#define C99_LIMIT_MACRO_2812 2812
#define C99_LIMIT_MACRO_2813 2813
#define C99_LIMIT_MACRO_2814 2814
#define C99_LIMIT_MACRO_2815 2815
#define C99_LIMIT_MACRO_2816 2816
#define C99_LIMIT_MACRO_2817 2817
#define C99_LIMIT_MACRO_2818 2818
#define C99_LIMIT_MACRO_2819 2819
#define C99_LIMIT_MACRO_2820 2820
#define C99_LIMIT_MACRO_2821 2821
#define C99_LIMIT_MACRO_2822 2822
#define C99_LIMIT_MACRO_2823 2823
#define C99_LIMIT_MACRO_2824 2824
#define C99_LIMIT_MACRO_2825 2825
#define C99_LIMIT_MACRO_2826 2826
#define C99_LIMIT_MACRO_2827 2827
#define C99_LIMIT_MACRO_2828 2828
#define C99_LIMIT_MACRO_2829 2829
#define C99_LIMIT_MACRO_2830 2830
#define C99_LIMIT_MACRO_2831 2831
#define C99_LIMIT_MACRO_2832 2832
#define C99_LIMIT_MACRO_2833 2833
#define C99_LIMIT_MACRO_2834 2834
#define C99_LIMIT_MACRO_2835 2835
#define C99_LIMIT_MACRO_2836 2836
#define C99_LIMIT_MACRO_2837 2837
#define C99_LIMIT_MACRO_2838 2838
#define C99_LIMIT_MACRO_2839 2839
#define C99_LIMIT_MACRO_2840 2840
#define C99_LIMIT_MACRO_2841 2841
#define C99_LIMIT_MACRO_2842 2842
#define C99_LIMIT_MACRO_2843 2843
#define C99_LIMIT_MACRO_2844 2844
#define C99_LIMIT_MACRO_2845 2845
#define C99_LIMIT_MACRO_2846 2846
#define C99_LIMIT_MACRO_2847 2847
#define C99_LIMIT_MACRO_2848 2848
#define C99_LIMIT_MACRO_2849 2849
#define C99_LIMIT_MACRO_2850 2850
#define C99_LIMIT_MACRO_2851 2851
#define C99_LIMIT_MACRO_2852 2852
#define C99_LIMIT_MACRO_2853 2853
#define C99_LIMIT_MACRO_2854 2854
#define C99_LIMIT_MACRO_2855 2855
#define C99_LIMIT_MACRO_2856 2856
#define C99_LIMIT_MACRO_2857 2857
#define C99_LIMIT_MACRO_2858 2858
#define C99_LIMIT_MACRO_2859 2859
#define C99_LIMIT_MACRO_2860 2860
#define C99_LIMIT_MACRO_2861 2861
#define C99_LIMIT_MACRO_2862 2862
#define C99_LIMIT_MACRO_2863 2863
#define C99_LIMIT_MACRO_2864 2864
#define C99_LIMIT_MACRO_2865 2865
#define C99_LIMIT_MACRO_2866 2866
#define C99_LIMIT_MACRO_2867 2867
#define C99_LIMIT_MACRO_2868 2868
#define C99_LIMIT_MACRO_2869 2869
#define C99_LIMIT_MACRO_2870 2870
#define C99_LIMIT_MACRO_2871 2871
#define C99_LIMIT_MACRO_2872 2872
#define C99_LIMIT_MACRO_2873 2873
#define C99_LIMIT_MACRO_2874 2874
#define C99_LIMIT_MACRO_2875 2875
#define C99_LIMIT_MACRO_2876 2876
#define C99_LIMIT_MACRO_2877 2877
#define C99_LIMIT_MACRO_2878 2878
#define C99_LIMIT_MACRO_2879 2879
#define C99_LIMIT_MACRO_2880 2880
#define C99_LIMIT_MACRO_2881 2881
#define C99_LIMIT_MACRO_2882 2882
#define C99_LIMIT_MACRO_2883 2883
#define C99_LIMIT_MACRO_2884 2884
#define C99_LIMIT_MACRO_2885 2885
#define C99_LIMIT_MACRO_2886 2886
#define C99_LIMIT_MACRO_2887 2887
#define C99_LIMIT_MACRO_2888 2888
#define C99_LIMIT_MACRO_2889 2889
#define C99_LIMIT_MACRO_2890 2890
#define C99_LIMIT_MACRO_2891 2891
#define C99_LIMIT_MACRO_2892 2892
#define C99_LIMIT_MACRO_2893 2893
#define C99_LIMIT_MACRO_2894 2894
#define C99_LIMIT_MACRO_2895 2895
#define C99_LIMIT_MACRO_2896 2896
#define C99_LIMIT_MACRO_2897 2897
#define C99_LIMIT_MACRO_2898 2898
#define C99_LIMIT_MACRO_2899 2899
#define C99_LIMIT_MACRO_2900 2900
#define C99_LIMIT_MACRO_2901 2901
#define C99_LIMIT_MACRO_2902 2902
#define C99_LIMIT_MACRO_2903 2903
#define C99_LIMIT_MACRO_2904 2904
#define C99_LIMIT_MACRO_2905 2905
#define C99_LIMIT_MACRO_2906 2906
#define C99_LIMIT_MACRO_2907 2907
#define C99_LIMIT_MACRO_2908 2908
#define C99_LIMIT_MACRO_2909 2909
#define C99_LIMIT_MACRO_2910 2910
#define C99_LIMIT_MACRO_2911 2911
#define C99_LIMIT_MACRO_2912 2912
#define C99_LIMIT_MACRO_2913 2913
#define C99_LIMIT_MACRO_2914 2914
#define C99_LIMIT_MACRO_2915 2915
#define C99_LIMIT_MACRO_2916 2916
#define C99_LIMIT_MACRO_2917 2917
#define C99_LIMIT_MACRO_2918 2918
#define C99_LIMIT_MACRO_2919 2919
#define C99_LIMIT_MACRO_2920 2920
#define C99_LIMIT_MACRO_2921 2921
#define C99_LIMIT_MACRO_2922 2922
#define C99_LIMIT_MACRO_2923 2923
#define C99_LIMIT_MACRO_2924 2924
#define C99_LIMIT_MACRO_2925 2925
#define C99_LIMIT_MACRO_2926 2926
#define C99_LIMIT_MACRO_2927 2927
#define C99_LIMIT_MACRO_2928 2928
#define C99_LIMIT_MACRO_2929 2929
#define C99_LIMIT_MACRO_2930 2930
#define C99_LIMIT_MACRO_2931 2931
#define C99_LIMIT_MACRO_2932 2932
#define C99_LIMIT_MACRO_2933 2933
#define C99_LIMIT_MACRO_2934 2934
#define C99_LIMIT_MACRO_2935 2935
#define C99_LIMIT_MACRO_2936 2936
#define C99_LIMIT_MACRO_2937 2937
#define C99_LIMIT_MACRO_2938 2938
#define C99_LIMIT_MACRO_2939 2939
#define C99_LIMIT_MACRO_2940 2940
#define C99_LIMIT_MACRO_2941 2941
#define C99_LIMIT_MACRO_2942 2942
#define C99_LIMIT_MACRO_2943 2943
#define C99_LIMIT_MACRO_2944 2944
#define C99_LIMIT_MACRO_2945 2945
#define C99_LIMIT_MACRO_2946 2946
#define C99_LIMIT_MACRO_2947 2947
#define C99_LIMIT_MACRO_2948 2948
#define C99_LIMIT_MACRO_2949 2949
#define C99_LIMIT_MACRO_2950 2950
#define C99_LIMIT_MACRO_2951 2951
#define C99_LIMIT_MACRO_2952 2952
#define C99_LIMIT_MACRO_2953 2953
#define C99_LIMIT_MACRO_2954 2954
#define C99_LIMIT_MACRO_2955 2955
#define C99_LIMIT_MACRO_2956 2956
#define C99_LIMIT_MACRO_2957 2957
#define C99_LIMIT_MACRO_2958 2958
#define C99_LIMIT_MACRO_2959 2959
#define C99_LIMIT_MACRO_2960 2960
#define C99_LIMIT_MACRO_2961 2961
#define C99_LIMIT_MACRO_2962 2962
#define C99_LIMIT_MACRO_2963 2963
#define C99_LIMIT_MACRO_2964 2964
#define C99_LIMIT_MACRO_2965 2965
#define C99_LIMIT_MACRO_2966 2966
#define C99_LIMIT_MACRO_2967 2967
#define C99_LIMIT_MACRO_2968 2968
#define C99_LIMIT_MACRO_2969 2969
#define C99_LIMIT_MACRO_2970 2970
#define C99_LIMIT_MACRO_2971 2971
#define C99_LIMIT_MACRO_2972 2972
#define C99_LIMIT_MACRO_2973 2973
#define C99_LIMIT_MACRO_2974 2974
#define C99_LIMIT_MACRO_2975 2975
#define C99_LIMIT_MACRO_2976 2976
#define C99_LIMIT_MACRO_2977 2977
#define C99_LIMIT_MACRO_2978 2978
#define C99_LIMIT_MACRO_2979 2979
#define C99_LIMIT_MACRO_2980 2980
#define C99_LIMIT_MACRO_2981 2981
#define C99_LIMIT_MACRO_2982 2982
#define C99_LIMIT_MACRO_2983 2983
#define C99_LIMIT_MACRO_2984 2984
#define C99_LIMIT_MACRO_2985 2985
#define C99_LIMIT_MACRO_2986 2986
#define C99_LIMIT_MACRO_2987 2987
#define C99_LIMIT_MACRO_2988 2988
#define C99_LIMIT_MACRO_2989 2989
#define C99_LIMIT_MACRO_2990 2990
#define C99_LIMIT_MACRO_2991 2991
#define C99_LIMIT_MACRO_2992 2992
#define C99_LIMIT_MACRO_2993 2993
#define C99_LIMIT_MACRO_2994 2994
#define C99_LIMIT_MACRO_2995 2995
#define C99_LIMIT_MACRO_2996 2996
#define C99_LIMIT_MACRO_2997 2997
#define C99_LIMIT_MACRO_2998 2998
#define C99_LIMIT_MACRO_2999 2999
#define C99_LIMIT_MACRO_3000 3000
#define C99_LIMIT_MACRO_3001 3001
#define C99_LIMIT_MACRO_3002 3002
#define C99_LIMIT_MACRO_3003 3003
#define C99_LIMIT_MACRO_3004 3004
#define C99_LIMIT_MACRO_3005 3005
#define C99_LIMIT_MACRO_3006 3006
#define C99_LIMIT_MACRO_3007 3007
#define C99_LIMIT_MACRO_3008 3008
#define C99_LIMIT_MACRO_3009 3009
#define C99_LIMIT_MACRO_3010 3010
#define C99_LIMIT_MACRO_3011 3011
#define C99_LIMIT_MACRO_3012 3012
#define C99_LIMIT_MACRO_3013 3013
#define C99_LIMIT_MACRO_3014 3014
#define C99_LIMIT_MACRO_3015 3015
#define C99_LIMIT_MACRO_3016 3016
#define C99_LIMIT_MACRO_3017 3017
#define C99_LIMIT_MACRO_3018 3018
#define C99_LIMIT_MACRO_3019 3019
#define C99_LIMIT_MACRO_3020 3020
#define C99_LIMIT_MACRO_3021 3021
#define C99_LIMIT_MACRO_3022 3022
#define C99_LIMIT_MACRO_3023 3023
#define C99_LIMIT_MACRO_3024 3024
#define C99_LIMIT_MACRO_3025 3025
#define C99_LIMIT_MACRO_3026 3026
#define C99_LIMIT_MACRO_3027 3027
#define C99_LIMIT_MACRO_3028 3028
#define C99_LIMIT_MACRO_3029 3029
#define C99_LIMIT_MACRO_3030 3030
#define C99_LIMIT_MACRO_3031 3031
#define C99_LIMIT_MACRO_3032 3032
#define C99_LIMIT_MACRO_3033 3033
#define C99_LIMIT_MACRO_3034 3034
#define C99_LIMIT_MACRO_3035 3035
#define C99_LIMIT_MACRO_3036 3036
#define C99_LIMIT_MACRO_3037 3037
#define C99_LIMIT_MACRO_3038 3038
#define C99_LIMIT_MACRO_3039 3039
#define C99_LIMIT_MACRO_3040 3040
#define C99_LIMIT_MACRO_3041 3041
#define C99_LIMIT_MACRO_3042 3042
#define C99_LIMIT_MACRO_3043 3043
#define C99_LIMIT_MACRO_3044 3044
#define C99_LIMIT_MACRO_3045 3045
#define C99_LIMIT_MACRO_3046 3046
#define C99_LIMIT_MACRO_3047 3047
#define C99_LIMIT_MACRO_3048 3048
#define C99_LIMIT_MACRO_3049 3049
#define C99_LIMIT_MACRO_3050 3050
#define C99_LIMIT_MACRO_3051 3051
#define C99_LIMIT_MACRO_3052 3052
#define C99_LIMIT_MACRO_3053 3053
#define C99_LIMIT_MACRO_3054 3054
#define C99_LIMIT_MACRO_3055 3055
#define C99_LIMIT_MACRO_3056 3056
#define C99_LIMIT_MACRO_3057 3057
#define C99_LIMIT_MACRO_3058 3058
#define C99_LIMIT_MACRO_3059 3059
#define C99_LIMIT_MACRO_3060 3060
#define C99_LIMIT_MACRO_3061 3061
#define C99_LIMIT_MACRO_3062 3062
#define C99_LIMIT_MACRO_3063 3063
#define C99_LIMIT_MACRO_3064 3064
#define C99_LIMIT_MACRO_3065 3065
#define C99_LIMIT_MACRO_3066 3066
#define C99_LIMIT_MACRO_3067 3067
#define C99_LIMIT_MACRO_3068 3068
#define C99_LIMIT_MACRO_3069 3069
#define C99_LIMIT_MACRO_3070 3070
#define C99_LIMIT_MACRO_3071 3071
#define C99_LIMIT_MACRO_3072 3072
#define C99_LIMIT_MACRO_3073 3073
#define C99_LIMIT_MACRO_3074 3074
#define C99_LIMIT_MACRO_3075 3075
#define C99_LIMIT_MACRO_3076 3076
#define C99_LIMIT_MACRO_3077 3077
#define C99_LIMIT_MACRO_3078 3078
#define C99_LIMIT_MACRO_3079 3079
#define C99_LIMIT_MACRO_3080 3080
#define C99_LIMIT_MACRO_3081 3081
#define C99_LIMIT_MACRO_3082 3082
#define C99_LIMIT_MACRO_3083 3083
#define C99_LIMIT_MACRO_3084 3084
#define C99_LIMIT_MACRO_3085 3085
#define C99_LIMIT_MACRO_3086 3086
#define C99_LIMIT_MACRO_3087 3087
#define C99_LIMIT_MACRO_3088 3088
#define C99_LIMIT_MACRO_3089 3089
#define C99_LIMIT_MACRO_3090 3090
#define C99_LIMIT_MACRO_3091 3091
#define C99_LIMIT_MACRO_3092 3092
#define C99_LIMIT_MACRO_3093 3093
#define C99_LIMIT_MACRO_3094 3094
#define C99_LIMIT_MACRO_3095 3095
#define C99_LIMIT_MACRO_3096 3096
#define C99_LIMIT_MACRO_3097 3097
#define C99_LIMIT_MACRO_3098 3098
#define C99_LIMIT_MACRO_3099 3099
#define C99_LIMIT_MACRO_3100 3100
#define C99_LIMIT_MACRO_3101 3101
#define C99_LIMIT_MACRO_3102 3102
#define C99_LIMIT_MACRO_3103 3103
#define C99_LIMIT_MACRO_3104 3104
#define C99_LIMIT_MACRO_3105 3105
#define C99_LIMIT_MACRO_3106 3106
#define C99_LIMIT_MACRO_3107 3107
#define C99_LIMIT_MACRO_3108 3108
#define C99_LIMIT_MACRO_3109 3109
#define C99_LIMIT_MACRO_3110 3110
#define C99_LIMIT_MACRO_3111 3111
#define C99_LIMIT_MACRO_3112 3112
#define C99_LIMIT_MACRO_3113 3113
#define C99_LIMIT_MACRO_3114 3114
#define C99_LIMIT_MACRO_3115 3115
#define C99_LIMIT_MACRO_3116 3116
#define C99_LIMIT_MACRO_3117 3117
#define C99_LIMIT_MACRO_3118 3118
#define C99_LIMIT_MACRO_3119 3119
#define C99_LIMIT_MACRO_3120 3120
#define C99_LIMIT_MACRO_3121 3121
#define C99_LIMIT_MACRO_3122 3122
#define C99_LIMIT_MACRO_3123 3123
#define C99_LIMIT_MACRO_3124 3124
#define C99_LIMIT_MACRO_3125 3125
#define C99_LIMIT_MACRO_3126 3126
#define C99_LIMIT_MACRO_3127 3127
#define C99_LIMIT_MACRO_3128 3128
#define C99_LIMIT_MACRO_3129 3129
#define C99_LIMIT_MACRO_3130 3130
#define C99_LIMIT_MACRO_3131 3131
#define C99_LIMIT_MACRO_3132 3132
#define C99_LIMIT_MACRO_3133 3133
#define C99_LIMIT_MACRO_3134 3134
#define C99_LIMIT_MACRO_3135 3135
#define C99_LIMIT_MACRO_3136 3136
#define C99_LIMIT_MACRO_3137 3137
#define C99_LIMIT_MACRO_3138 3138
#define C99_LIMIT_MACRO_3139 3139
#define C99_LIMIT_MACRO_3140 3140
#define C99_LIMIT_MACRO_3141 3141
#define C99_LIMIT_MACRO_3142 3142
#define C99_LIMIT_MACRO_3143 3143
#define C99_LIMIT_MACRO_3144 3144
#define C99_LIMIT_MACRO_3145 3145
#define C99_LIMIT_MACRO_3146 3146
#define C99_LIMIT_MACRO_3147 3147
#define C99_LIMIT_MACRO_3148 3148
#define C99_LIMIT_MACRO_3149 3149
#define C99_LIMIT_MACRO_3150 3150
#define C99_LIMIT_MACRO_3151 3151
#define C99_LIMIT_MACRO_3152 3152
#define C99_LIMIT_MACRO_3153 3153
#define C99_LIMIT_MACRO_3154 3154
#define C99_LIMIT_MACRO_3155 3155
#define C99_LIMIT_MACRO_3156 3156
#define C99_LIMIT_MACRO_3157 3157
#define C99_LIMIT_MACRO_3158 3158
#define C99_LIMIT_MACRO_3159 3159
#define C99_LIMIT_MACRO_3160 3160
#define C99_LIMIT_MACRO_3161 3161
#define C99_LIMIT_MACRO_3162 3162
#define C99_LIMIT_MACRO_3163 3163
#define C99_LIMIT_MACRO_3164 3164
#define C99_LIMIT_MACRO_3165 3165
#define C99_LIMIT_MACRO_3166 3166
#define C99_LIMIT_MACRO_3167 3167
#define C99_LIMIT_MACRO_3168 3168
#define C99_LIMIT_MACRO_3169 3169
#define C99_LIMIT_MACRO_3170 3170
#define C99_LIMIT_MACRO_3171 3171
#define C99_LIMIT_MACRO_3172 3172
#define C99_LIMIT_MACRO_3173 3173
#define C99_LIMIT_MACRO_3174 3174
#define C99_LIMIT_MACRO_3175 3175
#define C99_LIMIT_MACRO_3176 3176
#define C99_LIMIT_MACRO_3177 3177
#define C99_LIMIT_MACRO_3178 3178
#define C99_LIMIT_MACRO_3179 3179
#define C99_LIMIT_MACRO_3180 3180
#define C99_LIMIT_MACRO_3181 3181
#define C99_LIMIT_MACRO_3182 3182
#define C99_LIMIT_MACRO_3183 3183
#define C99_LIMIT_MACRO_3184 3184
#define C99_LIMIT_MACRO_3185 3185
#define C99_LIMIT_MACRO_3186 3186
#define C99_LIMIT_MACRO_3187 3187
#define C99_LIMIT_MACRO_3188 3188
#define C99_LIMIT_MACRO_3189 3189
#define C99_LIMIT_MACRO_3190 3190
#define C99_LIMIT_MACRO_3191 3191
#define C99_LIMIT_MACRO_3192 3192
#define C99_LIMIT_MACRO_3193 3193
#define C99_LIMIT_MACRO_3194 3194
#define C99_LIMIT_MACRO_3195 3195
#define C99_LIMIT_MACRO_3196 3196
#define C99_LIMIT_MACRO_3197 3197
#define C99_LIMIT_MACRO_3198 3198
#define C99_LIMIT_MACRO_3199 3199
#define C99_LIMIT_MACRO_3200 3200
#define C99_LIMIT_MACRO_3201 3201
#define C99_LIMIT_MACRO_3202 3202
#define C99_LIMIT_MACRO_3203 3203
#define C99_LIMIT_MACRO_3204 3204
#define C99_LIMIT_MACRO_3205 3205
#define C99_LIMIT_MACRO_3206 3206
#define C99_LIMIT_MACRO_3207 3207
#define C99_LIMIT_MACRO_3208 3208
#define C99_LIMIT_MACRO_3209 3209
#define C99_LIMIT_MACRO_3210 3210
#define C99_LIMIT_MACRO_3211 3211
#define C99_LIMIT_MACRO_3212 3212
#define C99_LIMIT_MACRO_3213 3213
#define C99_LIMIT_MACRO_3214 3214
#define C99_LIMIT_MACRO_3215 3215
#define C99_LIMIT_MACRO_3216 3216
#define C99_LIMIT_MACRO_3217 3217
#define C99_LIMIT_MACRO_3218 3218
#define C99_LIMIT_MACRO_3219 3219
#define C99_LIMIT_MACRO_3220 3220
#define C99_LIMIT_MACRO_3221 3221
#define C99_LIMIT_MACRO_3222 3222
#define C99_LIMIT_MACRO_3223 3223
#define C99_LIMIT_MACRO_3224 3224
#define C99_LIMIT_MACRO_3225 3225
#define C99_LIMIT_MACRO_3226 3226
#define C99_LIMIT_MACRO_3227 3227
#define C99_LIMIT_MACRO_3228 3228
#define C99_LIMIT_MACRO_3229 3229
#define C99_LIMIT_MACRO_3230 3230
#define C99_LIMIT_MACRO_3231 3231
#define C99_LIMIT_MACRO_3232 3232
#define C99_LIMIT_MACRO_3233 3233
#define C99_LIMIT_MACRO_3234 3234
#define C99_LIMIT_MACRO_3235 3235
#define C99_LIMIT_MACRO_3236 3236
#define C99_LIMIT_MACRO_3237 3237
#define C99_LIMIT_MACRO_3238 3238
#define C99_LIMIT_MACRO_3239 3239
#define C99_LIMIT_MACRO_3240 3240
#define C99_LIMIT_MACRO_3241 3241
#define C99_LIMIT_MACRO_3242 3242
#define C99_LIMIT_MACRO_3243 3243
#define C99_LIMIT_MACRO_3244 3244
#define C99_LIMIT_MACRO_3245 3245
#define C99_LIMIT_MACRO_3246 3246
#define C99_LIMIT_MACRO_3247 3247
#define C99_LIMIT_MACRO_3248 3248
#define C99_LIMIT_MACRO_3249 3249
#define C99_LIMIT_MACRO_3250 3250
#define C99_LIMIT_MACRO_3251 3251
#define C99_LIMIT_MACRO_3252 3252
#define C99_LIMIT_MACRO_3253 3253
#define C99_LIMIT_MACRO_3254 3254
#define C99_LIMIT_MACRO_3255 3255
#define C99_LIMIT_MACRO_3256 3256
#define C99_LIMIT_MACRO_3257 3257
#define C99_LIMIT_MACRO_3258 3258
#define C99_LIMIT_MACRO_3259 3259
#define C99_LIMIT_MACRO_3260 3260
#define C99_LIMIT_MACRO_3261 3261
#define C99_LIMIT_MACRO_3262 3262
#define C99_LIMIT_MACRO_3263 3263
#define C99_LIMIT_MACRO_3264 3264
#define C99_LIMIT_MACRO_3265 3265
#define C99_LIMIT_MACRO_3266 3266
#define C99_LIMIT_MACRO_3267 3267
#define C99_LIMIT_MACRO_3268 3268
#define C99_LIMIT_MACRO_3269 3269
#define C99_LIMIT_MACRO_3270 3270
#define C99_LIMIT_MACRO_3271 3271
#define C99_LIMIT_MACRO_3272 3272
#define C99_LIMIT_MACRO_3273 3273
#define C99_LIMIT_MACRO_3274 3274
#define C99_LIMIT_MACRO_3275 3275
#define C99_LIMIT_MACRO_3276 3276
#define C99_LIMIT_MACRO_3277 3277
#define C99_LIMIT_MACRO_3278 3278
#define C99_LIMIT_MACRO_3279 3279
#define C99_LIMIT_MACRO_3280 3280
#define C99_LIMIT_MACRO_3281 3281
#define C99_LIMIT_MACRO_3282 3282
#define C99_LIMIT_MACRO_3283 3283
#define C99_LIMIT_MACRO_3284 3284
#define C99_LIMIT_MACRO_3285 3285
#define C99_LIMIT_MACRO_3286 3286
#define C99_LIMIT_MACRO_3287 3287
#define C99_LIMIT_MACRO_3288 3288
#define C99_LIMIT_MACRO_3289 3289
#define C99_LIMIT_MACRO_3290 3290
#define C99_LIMIT_MACRO_3291 3291
#define C99_LIMIT_MACRO_3292 3292
#define C99_LIMIT_MACRO_3293 3293
#define C99_LIMIT_MACRO_3294 3294
#define C99_LIMIT_MACRO_3295 3295
#define C99_LIMIT_MACRO_3296 3296
#define C99_LIMIT_MACRO_3297 3297
#define C99_LIMIT_MACRO_3298 3298
#define C99_LIMIT_MACRO_3299 3299
#define C99_LIMIT_MACRO_3300 3300
#define C99_LIMIT_MACRO_3301 3301
#define C99_LIMIT_MACRO_3302 3302
#define C99_LIMIT_MACRO_3303 3303
#define C99_LIMIT_MACRO_3304 3304
#define C99_LIMIT_MACRO_3305 3305
#define C99_LIMIT_MACRO_3306 3306
#define C99_LIMIT_MACRO_3307 3307
#define C99_LIMIT_MACRO_3308 3308
#define C99_LIMIT_MACRO_3309 3309
#define C99_LIMIT_MACRO_3310 3310
#define C99_LIMIT_MACRO_3311 3311
#define C99_LIMIT_MACRO_3312 3312
#define C99_LIMIT_MACRO_3313 3313
#define C99_LIMIT_MACRO_3314 3314
#define C99_LIMIT_MACRO_3315 3315
#define C99_LIMIT_MACRO_3316 3316
#define C99_LIMIT_MACRO_3317 3317
#define C99_LIMIT_MACRO_3318 3318
#define C99_LIMIT_MACRO_3319 3319
#define C99_LIMIT_MACRO_3320 3320
#define C99_LIMIT_MACRO_3321 3321
#define C99_LIMIT_MACRO_3322 3322
#define C99_LIMIT_MACRO_3323 3323
#define C99_LIMIT_MACRO_3324 3324
#define C99_LIMIT_MACRO_3325 3325
#define C99_LIMIT_MACRO_3326 3326
#define C99_LIMIT_MACRO_3327 3327
#define C99_LIMIT_MACRO_3328 3328
#define C99_LIMIT_MACRO_3329 3329
#define C99_LIMIT_MACRO_3330 3330
#define C99_LIMIT_MACRO_3331 3331
#define C99_LIMIT_MACRO_3332 3332
#define C99_LIMIT_MACRO_3333 3333
#define C99_LIMIT_MACRO_3334 3334
#define C99_LIMIT_MACRO_3335 3335
#define C99_LIMIT_MACRO_3336 3336
#define C99_LIMIT_MACRO_3337 3337
#define C99_LIMIT_MACRO_3338 3338
#define C99_LIMIT_MACRO_3339 3339
#define C99_LIMIT_MACRO_3340 3340
#define C99_LIMIT_MACRO_3341 3341
#define C99_LIMIT_MACRO_3342 3342
#define C99_LIMIT_MACRO_3343 3343
#define C99_LIMIT_MACRO_3344 3344
#define C99_LIMIT_MACRO_3345 3345
#define C99_LIMIT_MACRO_3346 3346
#define C99_LIMIT_MACRO_3347 3347
#define C99_LIMIT_MACRO_3348 3348
#define C99_LIMIT_MACRO_3349 3349
#define C99_LIMIT_MACRO_3350 3350
#define C99_LIMIT_MACRO_3351 3351
#define C99_LIMIT_MACRO_3352 3352
#define C99_LIMIT_MACRO_3353 3353
#define C99_LIMIT_MACRO_3354 3354
#define C99_LIMIT_MACRO_3355 3355
#define C99_LIMIT_MACRO_3356 3356
#define C99_LIMIT_MACRO_3357 3357
#define C99_LIMIT_MACRO_3358 3358
#define C99_LIMIT_MACRO_3359 3359
#define C99_LIMIT_MACRO_3360 3360
#define C99_LIMIT_MACRO_3361 3361
#define C99_LIMIT_MACRO_3362 3362
#define C99_LIMIT_MACRO_3363 3363
#define C99_LIMIT_MACRO_3364 3364
#define C99_LIMIT_MACRO_3365 3365
#define C99_LIMIT_MACRO_3366 3366
#define C99_LIMIT_MACRO_3367 3367
#define C99_LIMIT_MACRO_3368 3368
#define C99_LIMIT_MACRO_3369 3369
#define C99_LIMIT_MACRO_3370 3370
#define C99_LIMIT_MACRO_3371 3371
#define C99_LIMIT_MACRO_3372 3372
#define C99_LIMIT_MACRO_3373 3373
#define C99_LIMIT_MACRO_3374 3374
#define C99_LIMIT_MACRO_3375 3375
#define C99_LIMIT_MACRO_3376 3376
#define C99_LIMIT_MACRO_3377 3377
#define C99_LIMIT_MACRO_3378 3378
#define C99_LIMIT_MACRO_3379 3379
#define C99_LIMIT_MACRO_3380 3380
#define C99_LIMIT_MACRO_3381 3381
#define C99_LIMIT_MACRO_3382 3382
#define C99_LIMIT_MACRO_3383 3383
#define C99_LIMIT_MACRO_3384 3384
#define C99_LIMIT_MACRO_3385 3385
#define C99_LIMIT_MACRO_3386 3386
#define C99_LIMIT_MACRO_3387 3387
#define C99_LIMIT_MACRO_3388 3388
#define C99_LIMIT_MACRO_3389 3389
#define C99_LIMIT_MACRO_3390 3390
#define C99_LIMIT_MACRO_3391 3391
#define C99_LIMIT_MACRO_3392 3392
#define C99_LIMIT_MACRO_3393 3393
#define C99_LIMIT_MACRO_3394 3394
#define C99_LIMIT_MACRO_3395 3395
#define C99_LIMIT_MACRO_3396 3396
#define C99_LIMIT_MACRO_3397 3397
#define C99_LIMIT_MACRO_3398 3398
#define C99_LIMIT_MACRO_3399 3399
#define C99_LIMIT_MACRO_3400 3400
#define C99_LIMIT_MACRO_3401 3401
#define C99_LIMIT_MACRO_3402 3402
#define C99_LIMIT_MACRO_3403 3403
#define C99_LIMIT_MACRO_3404 3404
#define C99_LIMIT_MACRO_3405 3405
#define C99_LIMIT_MACRO_3406 3406
#define C99_LIMIT_MACRO_3407 3407
#define C99_LIMIT_MACRO_3408 3408
#define C99_LIMIT_MACRO_3409 3409
#define C99_LIMIT_MACRO_3410 3410
#define C99_LIMIT_MACRO_3411 3411
#define C99_LIMIT_MACRO_3412 3412
#define C99_LIMIT_MACRO_3413 3413
#define C99_LIMIT_MACRO_3414 3414
#define C99_LIMIT_MACRO_3415 3415
#define C99_LIMIT_MACRO_3416 3416
#define C99_LIMIT_MACRO_3417 3417
#define C99_LIMIT_MACRO_3418 3418
#define C99_LIMIT_MACRO_3419 3419
#define C99_LIMIT_MACRO_3420 3420
#define C99_LIMIT_MACRO_3421 3421
#define C99_LIMIT_MACRO_3422 3422
#define C99_LIMIT_MACRO_3423 3423
#define C99_LIMIT_MACRO_3424 3424
#define C99_LIMIT_MACRO_3425 3425
#define C99_LIMIT_MACRO_3426 3426
#define C99_LIMIT_MACRO_3427 3427
#define C99_LIMIT_MACRO_3428 3428
#define C99_LIMIT_MACRO_3429 3429
#define C99_LIMIT_MACRO_3430 3430
#define C99_LIMIT_MACRO_3431 3431
#define C99_LIMIT_MACRO_3432 3432
#define C99_LIMIT_MACRO_3433 3433
#define C99_LIMIT_MACRO_3434 3434
#define C99_LIMIT_MACRO_3435 3435
#define C99_LIMIT_MACRO_3436 3436
#define C99_LIMIT_MACRO_3437 3437
#define C99_LIMIT_MACRO_3438 3438
#define C99_LIMIT_MACRO_3439 3439
#define C99_LIMIT_MACRO_3440 3440
#define C99_LIMIT_MACRO_3441 3441
#define C99_LIMIT_MACRO_3442 3442
#define C99_LIMIT_MACRO_3443 3443
#define C99_LIMIT_MACRO_3444 3444
#define C99_LIMIT_MACRO_3445 3445
#define C99_LIMIT_MACRO_3446 3446
#define C99_LIMIT_MACRO_3447 3447
#define C99_LIMIT_MACRO_3448 3448
#define C99_LIMIT_MACRO_3449 3449
#define C99_LIMIT_MACRO_3450 3450
#define C99_LIMIT_MACRO_3451 3451
#define C99_LIMIT_MACRO_3452 3452
#define C99_LIMIT_MACRO_3453 3453
#define C99_LIMIT_MACRO_3454 3454
#define C99_LIMIT_MACRO_3455 3455
#define C99_LIMIT_MACRO_3456 3456
#define C99_LIMIT_MACRO_3457 3457
#define C99_LIMIT_MACRO_3458 3458
#define C99_LIMIT_MACRO_3459 3459
#define C99_LIMIT_MACRO_3460 3460
#define C99_LIMIT_MACRO_3461 3461
#define C99_LIMIT_MACRO_3462 3462
#define C99_LIMIT_MACRO_3463 3463
#define C99_LIMIT_MACRO_3464 3464
#define C99_LIMIT_MACRO_3465 3465
#define C99_LIMIT_MACRO_3466 3466
#define C99_LIMIT_MACRO_3467 3467
#define C99_LIMIT_MACRO_3468 3468
#define C99_LIMIT_MACRO_3469 3469
#define C99_LIMIT_MACRO_3470 3470
#define C99_LIMIT_MACRO_3471 3471
#define C99_LIMIT_MACRO_3472 3472
#define C99_LIMIT_MACRO_3473 3473
#define C99_LIMIT_MACRO_3474 3474
#define C99_LIMIT_MACRO_3475 3475
#define C99_LIMIT_MACRO_3476 3476
#define C99_LIMIT_MACRO_3477 3477
#define C99_LIMIT_MACRO_3478 3478
#define C99_LIMIT_MACRO_3479 3479
#define C99_LIMIT_MACRO_3480 3480
#define C99_LIMIT_MACRO_3481 3481
#define C99_LIMIT_MACRO_3482 3482
#define C99_LIMIT_MACRO_3483 3483
#define C99_LIMIT_MACRO_3484 3484
#define C99_LIMIT_MACRO_3485 3485
#define C99_LIMIT_MACRO_3486 3486
#define C99_LIMIT_MACRO_3487 3487
#define C99_LIMIT_MACRO_3488 3488
#define C99_LIMIT_MACRO_3489 3489
#define C99_LIMIT_MACRO_3490 3490
#define C99_LIMIT_MACRO_3491 3491
#define C99_LIMIT_MACRO_3492 3492
#define C99_LIMIT_MACRO_3493 3493
#define C99_LIMIT_MACRO_3494 3494
#define C99_LIMIT_MACRO_3495 3495
#define C99_LIMIT_MACRO_3496 3496
#define C99_LIMIT_MACRO_3497 3497
#define C99_LIMIT_MACRO_3498 3498
#define C99_LIMIT_MACRO_3499 3499
#define C99_LIMIT_MACRO_3500 3500
#define C99_LIMIT_MACRO_3501 3501
#define C99_LIMIT_MACRO_3502 3502
#define C99_LIMIT_MACRO_3503 3503
#define C99_LIMIT_MACRO_3504 3504
#define C99_LIMIT_MACRO_3505 3505
#define C99_LIMIT_MACRO_3506 3506
#define C99_LIMIT_MACRO_3507 3507
#define C99_LIMIT_MACRO_3508 3508
#define C99_LIMIT_MACRO_3509 3509
#define C99_LIMIT_MACRO_3510 3510
#define C99_LIMIT_MACRO_3511 3511
#define C99_LIMIT_MACRO_3512 3512
#define C99_LIMIT_MACRO_3513 3513
#define C99_LIMIT_MACRO_3514 3514
#define C99_LIMIT_MACRO_3515 3515
#define C99_LIMIT_MACRO_3516 3516
#define C99_LIMIT_MACRO_3517 3517
#define C99_LIMIT_MACRO_3518 3518
#define C99_LIMIT_MACRO_3519 3519
#define C99_LIMIT_MACRO_3520 3520
#define C99_LIMIT_MACRO_3521 3521
#define C99_LIMIT_MACRO_3522 3522
#define C99_LIMIT_MACRO_3523 3523
#define C99_LIMIT_MACRO_3524 3524
#define C99_LIMIT_MACRO_3525 3525
#define C99_LIMIT_MACRO_3526 3526
#define C99_LIMIT_MACRO_3527 3527
#define C99_LIMIT_MACRO_3528 3528
#define C99_LIMIT_MACRO_3529 3529
#define C99_LIMIT_MACRO_3530 3530
#define C99_LIMIT_MACRO_3531 3531
#define C99_LIMIT_MACRO_3532 3532
#define C99_LIMIT_MACRO_3533 3533
#define C99_LIMIT_MACRO_3534 3534
#define C99_LIMIT_MACRO_3535 3535
#define C99_LIMIT_MACRO_3536 3536
#define C99_LIMIT_MACRO_3537 3537
#define C99_LIMIT_MACRO_3538 3538
#define C99_LIMIT_MACRO_3539 3539
#define C99_LIMIT_MACRO_3540 3540
#define C99_LIMIT_MACRO_3541 3541
#define C99_LIMIT_MACRO_3542 3542
#define C99_LIMIT_MACRO_3543 3543
#define C99_LIMIT_MACRO_3544 3544
#define C99_LIMIT_MACRO_3545 3545
#define C99_LIMIT_MACRO_3546 3546
#define C99_LIMIT_MACRO_3547 3547
#define C99_LIMIT_MACRO_3548 3548
#define C99_LIMIT_MACRO_3549 3549
#define C99_LIMIT_MACRO_3550 3550
#define C99_LIMIT_MACRO_3551 3551
#define C99_LIMIT_MACRO_3552 3552
#define C99_LIMIT_MACRO_3553 3553
#define C99_LIMIT_MACRO_3554 3554
#define C99_LIMIT_MACRO_3555 3555
#define C99_LIMIT_MACRO_3556 3556
#define C99_LIMIT_MACRO_3557 3557
#define C99_LIMIT_MACRO_3558 3558
#define C99_LIMIT_MACRO_3559 3559
#define C99_LIMIT_MACRO_3560 3560
#define C99_LIMIT_MACRO_3561 3561
#define C99_LIMIT_MACRO_3562 3562
#define C99_LIMIT_MACRO_3563 3563
#define C99_LIMIT_MACRO_3564 3564
#define C99_LIMIT_MACRO_3565 3565
#define C99_LIMIT_MACRO_3566 3566
#define C99_LIMIT_MACRO_3567 3567
#define C99_LIMIT_MACRO_3568 3568
#define C99_LIMIT_MACRO_3569 3569
#define C99_LIMIT_MACRO_3570 3570
#define C99_LIMIT_MACRO_3571 3571
#define C99_LIMIT_MACRO_3572 3572
#define C99_LIMIT_MACRO_3573 3573
#define C99_LIMIT_MACRO_3574 3574
#define C99_LIMIT_MACRO_3575 3575
#define C99_LIMIT_MACRO_3576 3576
#define C99_LIMIT_MACRO_3577 3577
#define C99_LIMIT_MACRO_3578 3578
#define C99_LIMIT_MACRO_3579 3579
#define C99_LIMIT_MACRO_3580 3580
#define C99_LIMIT_MACRO_3581 3581
#define C99_LIMIT_MACRO_3582 3582
#define C99_LIMIT_MACRO_3583 3583
#define C99_LIMIT_MACRO_3584 3584
#define C99_LIMIT_MACRO_3585 3585
#define C99_LIMIT_MACRO_3586 3586
#define C99_LIMIT_MACRO_3587 3587
#define C99_LIMIT_MACRO_3588 3588
#define C99_LIMIT_MACRO_3589 3589
#define C99_LIMIT_MACRO_3590 3590
#define C99_LIMIT_MACRO_3591 3591
#define C99_LIMIT_MACRO_3592 3592
#define C99_LIMIT_MACRO_3593 3593
#define C99_LIMIT_MACRO_3594 3594
#define C99_LIMIT_MACRO_3595 3595
#define C99_LIMIT_MACRO_3596 3596
#define C99_LIMIT_MACRO_3597 3597
#define C99_LIMIT_MACRO_3598 3598
#define C99_LIMIT_MACRO_3599 3599
#define C99_LIMIT_MACRO_3600 3600
#define C99_LIMIT_MACRO_3601 3601
#define C99_LIMIT_MACRO_3602 3602
#define C99_LIMIT_MACRO_3603 3603
#define C99_LIMIT_MACRO_3604 3604
#define C99_LIMIT_MACRO_3605 3605
#define C99_LIMIT_MACRO_3606 3606
#define C99_LIMIT_MACRO_3607 3607
#define C99_LIMIT_MACRO_3608 3608
#define C99_LIMIT_MACRO_3609 3609
#define C99_LIMIT_MACRO_3610 3610
#define C99_LIMIT_MACRO_3611 3611
#define C99_LIMIT_MACRO_3612 3612
#define C99_LIMIT_MACRO_3613 3613
#define C99_LIMIT_MACRO_3614 3614
#define C99_LIMIT_MACRO_3615 3615
#define C99_LIMIT_MACRO_3616 3616
#define C99_LIMIT_MACRO_3617 3617
#define C99_LIMIT_MACRO_3618 3618
#define C99_LIMIT_MACRO_3619 3619
#define C99_LIMIT_MACRO_3620 3620
#define C99_LIMIT_MACRO_3621 3621
#define C99_LIMIT_MACRO_3622 3622
#define C99_LIMIT_MACRO_3623 3623
#define C99_LIMIT_MACRO_3624 3624
#define C99_LIMIT_MACRO_3625 3625
#define C99_LIMIT_MACRO_3626 3626
#define C99_LIMIT_MACRO_3627 3627
#define C99_LIMIT_MACRO_3628 3628
#define C99_LIMIT_MACRO_3629 3629
#define C99_LIMIT_MACRO_3630 3630
#define C99_LIMIT_MACRO_3631 3631
#define C99_LIMIT_MACRO_3632 3632
#define C99_LIMIT_MACRO_3633 3633
#define C99_LIMIT_MACRO_3634 3634
#define C99_LIMIT_MACRO_3635 3635
#define C99_LIMIT_MACRO_3636 3636
#define C99_LIMIT_MACRO_3637 3637
#define C99_LIMIT_MACRO_3638 3638
#define C99_LIMIT_MACRO_3639 3639
#define C99_LIMIT_MACRO_3640 3640
#define C99_LIMIT_MACRO_3641 3641
#define C99_LIMIT_MACRO_3642 3642
#define C99_LIMIT_MACRO_3643 3643
#define C99_LIMIT_MACRO_3644 3644
#define C99_LIMIT_MACRO_3645 3645
#define C99_LIMIT_MACRO_3646 3646
#define C99_LIMIT_MACRO_3647 3647
#define C99_LIMIT_MACRO_3648 3648
#define C99_LIMIT_MACRO_3649 3649
#define C99_LIMIT_MACRO_3650 3650
#define C99_LIMIT_MACRO_3651 3651
#define C99_LIMIT_MACRO_3652 3652
#define C99_LIMIT_MACRO_3653 3653
#define C99_LIMIT_MACRO_3654 3654
#define C99_LIMIT_MACRO_3655 3655
#define C99_LIMIT_MACRO_3656 3656
#define C99_LIMIT_MACRO_3657 3657
#define C99_LIMIT_MACRO_3658 3658
#define C99_LIMIT_MACRO_3659 3659
#define C99_LIMIT_MACRO_3660 3660
#define C99_LIMIT_MACRO_3661 3661
#define C99_LIMIT_MACRO_3662 3662
#define C99_LIMIT_MACRO_3663 3663
#define C99_LIMIT_MACRO_3664 3664
#define C99_LIMIT_MACRO_3665 3665
#define C99_LIMIT_MACRO_3666 3666
#define C99_LIMIT_MACRO_3667 3667
#define C99_LIMIT_MACRO_3668 3668
#define C99_LIMIT_MACRO_3669 3669
#define C99_LIMIT_MACRO_3670 3670
#define C99_LIMIT_MACRO_3671 3671
#define C99_LIMIT_MACRO_3672 3672
#define C99_LIMIT_MACRO_3673 3673
#define C99_LIMIT_MACRO_3674 3674
#define C99_LIMIT_MACRO_3675 3675
#define C99_LIMIT_MACRO_3676 3676
#define C99_LIMIT_MACRO_3677 3677
#define C99_LIMIT_MACRO_3678 3678
#define C99_LIMIT_MACRO_3679 3679
#define C99_LIMIT_MACRO_3680 3680
#define C99_LIMIT_MACRO_3681 3681
#define C99_LIMIT_MACRO_3682 3682
#define C99_LIMIT_MACRO_3683 3683
#define C99_LIMIT_MACRO_3684 3684
#define C99_LIMIT_MACRO_3685 3685
#define C99_LIMIT_MACRO_3686 3686
#define C99_LIMIT_MACRO_3687 3687
#define C99_LIMIT_MACRO_3688 3688
#define C99_LIMIT_MACRO_3689 3689
#define C99_LIMIT_MACRO_3690 3690
#define C99_LIMIT_MACRO_3691 3691
#define C99_LIMIT_MACRO_3692 3692
#define C99_LIMIT_MACRO_3693 3693
#define C99_LIMIT_MACRO_3694 3694
#define C99_LIMIT_MACRO_3695 3695
#define C99_LIMIT_MACRO_3696 3696
#define C99_LIMIT_MACRO_3697 3697
#define C99_LIMIT_MACRO_3698 3698
#define C99_LIMIT_MACRO_3699 3699
#define C99_LIMIT_MACRO_3700 3700
#define C99_LIMIT_MACRO_3701 3701
#define C99_LIMIT_MACRO_3702 3702
#define C99_LIMIT_MACRO_3703 3703
#define C99_LIMIT_MACRO_3704 3704
#define C99_LIMIT_MACRO_3705 3705
#define C99_LIMIT_MACRO_3706 3706
#define C99_LIMIT_MACRO_3707 3707
#define C99_LIMIT_MACRO_3708 3708
#define C99_LIMIT_MACRO_3709 3709
#define C99_LIMIT_MACRO_3710 3710
#define C99_LIMIT_MACRO_3711 3711
#define C99_LIMIT_MACRO_3712 3712
#define C99_LIMIT_MACRO_3713 3713
#define C99_LIMIT_MACRO_3714 3714
#define C99_LIMIT_MACRO_3715 3715
#define C99_LIMIT_MACRO_3716 3716
#define C99_LIMIT_MACRO_3717 3717
#define C99_LIMIT_MACRO_3718 3718
#define C99_LIMIT_MACRO_3719 3719
#define C99_LIMIT_MACRO_3720 3720
#define C99_LIMIT_MACRO_3721 3721
#define C99_LIMIT_MACRO_3722 3722
#define C99_LIMIT_MACRO_3723 3723
#define C99_LIMIT_MACRO_3724 3724
#define C99_LIMIT_MACRO_3725 3725
#define C99_LIMIT_MACRO_3726 3726
#define C99_LIMIT_MACRO_3727 3727
#define C99_LIMIT_MACRO_3728 3728
#define C99_LIMIT_MACRO_3729 3729
#define C99_LIMIT_MACRO_3730 3730
#define C99_LIMIT_MACRO_3731 3731
#define C99_LIMIT_MACRO_3732 3732
#define C99_LIMIT_MACRO_3733 3733
#define C99_LIMIT_MACRO_3734 3734
#define C99_LIMIT_MACRO_3735 3735
#define C99_LIMIT_MACRO_3736 3736
#define C99_LIMIT_MACRO_3737 3737
#define C99_LIMIT_MACRO_3738 3738
#define C99_LIMIT_MACRO_3739 3739
#define C99_LIMIT_MACRO_3740 3740
#define C99_LIMIT_MACRO_3741 3741
#define C99_LIMIT_MACRO_3742 3742
#define C99_LIMIT_MACRO_3743 3743
#define C99_LIMIT_MACRO_3744 3744
#define C99_LIMIT_MACRO_3745 3745
#define C99_LIMIT_MACRO_3746 3746
#define C99_LIMIT_MACRO_3747 3747
#define C99_LIMIT_MACRO_3748 3748
#define C99_LIMIT_MACRO_3749 3749
#define C99_LIMIT_MACRO_3750 3750
#define C99_LIMIT_MACRO_3751 3751
#define C99_LIMIT_MACRO_3752 3752
#define C99_LIMIT_MACRO_3753 3753
#define C99_LIMIT_MACRO_3754 3754
#define C99_LIMIT_MACRO_3755 3755
#define C99_LIMIT_MACRO_3756 3756
#define C99_LIMIT_MACRO_3757 3757
#define C99_LIMIT_MACRO_3758 3758
#define C99_LIMIT_MACRO_3759 3759
#define C99_LIMIT_MACRO_3760 3760
#define C99_LIMIT_MACRO_3761 3761
#define C99_LIMIT_MACRO_3762 3762
#define C99_LIMIT_MACRO_3763 3763
#define C99_LIMIT_MACRO_3764 3764
#define C99_LIMIT_MACRO_3765 3765
#define C99_LIMIT_MACRO_3766 3766
#define C99_LIMIT_MACRO_3767 3767
#define C99_LIMIT_MACRO_3768 3768
#define C99_LIMIT_MACRO_3769 3769
#define C99_LIMIT_MACRO_3770 3770
#define C99_LIMIT_MACRO_3771 3771
#define C99_LIMIT_MACRO_3772 3772
#define C99_LIMIT_MACRO_3773 3773
#define C99_LIMIT_MACRO_3774 3774
#define C99_LIMIT_MACRO_3775 3775
#define C99_LIMIT_MACRO_3776 3776
#define C99_LIMIT_MACRO_3777 3777
#define C99_LIMIT_MACRO_3778 3778
#define C99_LIMIT_MACRO_3779 3779
#define C99_LIMIT_MACRO_3780 3780
#define C99_LIMIT_MACRO_3781 3781
#define C99_LIMIT_MACRO_3782 3782
#define C99_LIMIT_MACRO_3783 3783
#define C99_LIMIT_MACRO_3784 3784
#define C99_LIMIT_MACRO_3785 3785
#define C99_LIMIT_MACRO_3786 3786
#define C99_LIMIT_MACRO_3787 3787
#define C99_LIMIT_MACRO_3788 3788
#define C99_LIMIT_MACRO_3789 3789
#define C99_LIMIT_MACRO_3790 3790
#define C99_LIMIT_MACRO_3791 3791
#define C99_LIMIT_MACRO_3792 3792
#define C99_LIMIT_MACRO_3793 3793
#define C99_LIMIT_MACRO_3794 3794
#define C99_LIMIT_MACRO_3795 3795
#define C99_LIMIT_MACRO_3796 3796
#define C99_LIMIT_MACRO_3797 3797
#define C99_LIMIT_MACRO_3798 3798
#define C99_LIMIT_MACRO_3799 3799
#define C99_LIMIT_MACRO_3800 3800
#define C99_LIMIT_MACRO_3801 3801
#define C99_LIMIT_MACRO_3802 3802
#define C99_LIMIT_MACRO_3803 3803
#define C99_LIMIT_MACRO_3804 3804
#define C99_LIMIT_MACRO_3805 3805
#define C99_LIMIT_MACRO_3806 3806
#define C99_LIMIT_MACRO_3807 3807
#define C99_LIMIT_MACRO_3808 3808
#define C99_LIMIT_MACRO_3809 3809
#define C99_LIMIT_MACRO_3810 3810
#define C99_LIMIT_MACRO_3811 3811
#define C99_LIMIT_MACRO_3812 3812
#define C99_LIMIT_MACRO_3813 3813
#define C99_LIMIT_MACRO_3814 3814
#define C99_LIMIT_MACRO_3815 3815
#define C99_LIMIT_MACRO_3816 3816
#define C99_LIMIT_MACRO_3817 3817
#define C99_LIMIT_MACRO_3818 3818
#define C99_LIMIT_MACRO_3819 3819
#define C99_LIMIT_MACRO_3820 3820
#define C99_LIMIT_MACRO_3821 3821
#define C99_LIMIT_MACRO_3822 3822
#define C99_LIMIT_MACRO_3823 3823
#define C99_LIMIT_MACRO_3824 3824
#define C99_LIMIT_MACRO_3825 3825
#define C99_LIMIT_MACRO_3826 3826
#define C99_LIMIT_MACRO_3827 3827
#define C99_LIMIT_MACRO_3828 3828
#define C99_LIMIT_MACRO_3829 3829
#define C99_LIMIT_MACRO_3830 3830
#define C99_LIMIT_MACRO_3831 3831
#define C99_LIMIT_MACRO_3832 3832
#define C99_LIMIT_MACRO_3833 3833
#define C99_LIMIT_MACRO_3834 3834
#define C99_LIMIT_MACRO_3835 3835
#define C99_LIMIT_MACRO_3836 3836
#define C99_LIMIT_MACRO_3837 3837
#define C99_LIMIT_MACRO_3838 3838
#define C99_LIMIT_MACRO_3839 3839
#define C99_LIMIT_MACRO_3840 3840
#define C99_LIMIT_MACRO_3841 3841
#define C99_LIMIT_MACRO_3842 3842
#define C99_LIMIT_MACRO_3843 3843
#define C99_LIMIT_MACRO_3844 3844
#define C99_LIMIT_MACRO_3845 3845
#define C99_LIMIT_MACRO_3846 3846
#define C99_LIMIT_MACRO_3847 3847
#define C99_LIMIT_MACRO_3848 3848
#define C99_LIMIT_MACRO_3849 3849
#define C99_LIMIT_MACRO_3850 3850
#define C99_LIMIT_MACRO_3851 3851
#define C99_LIMIT_MACRO_3852 3852
#define C99_LIMIT_MACRO_3853 3853
#define C99_LIMIT_MACRO_3854 3854
#define C99_LIMIT_MACRO_3855 3855
#define C99_LIMIT_MACRO_3856 3856
#define C99_LIMIT_MACRO_3857 3857
#define C99_LIMIT_MACRO_3858 3858
#define C99_LIMIT_MACRO_3859 3859
#define C99_LIMIT_MACRO_3860 3860
#define C99_LIMIT_MACRO_3861 3861
#define C99_LIMIT_MACRO_3862 3862
#define C99_LIMIT_MACRO_3863 3863
#define C99_LIMIT_MACRO_3864 3864
#define C99_LIMIT_MACRO_3865 3865
#define C99_LIMIT_MACRO_3866 3866
#define C99_LIMIT_MACRO_3867 3867
#define C99_LIMIT_MACRO_3868 3868
#define C99_LIMIT_MACRO_3869 3869
#define C99_LIMIT_MACRO_3870 3870
#define C99_LIMIT_MACRO_3871 3871
#define C99_LIMIT_MACRO_3872 3872
#define C99_LIMIT_MACRO_3873 3873
#define C99_LIMIT_MACRO_3874 3874
#define C99_LIMIT_MACRO_3875 3875
#define C99_LIMIT_MACRO_3876 3876
#define C99_LIMIT_MACRO_3877 3877
#define C99_LIMIT_MACRO_3878 3878
#define C99_LIMIT_MACRO_3879 3879
#define C99_LIMIT_MACRO_3880 3880
#define C99_LIMIT_MACRO_3881 3881
#define C99_LIMIT_MACRO_3882 3882
#define C99_LIMIT_MACRO_3883 3883
#define C99_LIMIT_MACRO_3884 3884
#define C99_LIMIT_MACRO_3885 3885
#define C99_LIMIT_MACRO_3886 3886
#define C99_LIMIT_MACRO_3887 3887
#define C99_LIMIT_MACRO_3888 3888
#define C99_LIMIT_MACRO_3889 3889
#define C99_LIMIT_MACRO_3890 3890
#define C99_LIMIT_MACRO_3891 3891
#define C99_LIMIT_MACRO_3892 3892
#define C99_LIMIT_MACRO_3893 3893
#define C99_LIMIT_MACRO_3894 3894
#define C99_LIMIT_MACRO_3895 3895
#define C99_LIMIT_MACRO_3896 3896
#define C99_LIMIT_MACRO_3897 3897
#define C99_LIMIT_MACRO_3898 3898
#define C99_LIMIT_MACRO_3899 3899
#define C99_LIMIT_MACRO_3900 3900
#define C99_LIMIT_MACRO_3901 3901
#define C99_LIMIT_MACRO_3902 3902
#define C99_LIMIT_MACRO_3903 3903
#define C99_LIMIT_MACRO_3904 3904
#define C99_LIMIT_MACRO_3905 3905
#define C99_LIMIT_MACRO_3906 3906
#define C99_LIMIT_MACRO_3907 3907
#define C99_LIMIT_MACRO_3908 3908
#define C99_LIMIT_MACRO_3909 3909
#define C99_LIMIT_MACRO_3910 3910
#define C99_LIMIT_MACRO_3911 3911
#define C99_LIMIT_MACRO_3912 3912
#define C99_LIMIT_MACRO_3913 3913
#define C99_LIMIT_MACRO_3914 3914
#define C99_LIMIT_MACRO_3915 3915
#define C99_LIMIT_MACRO_3916 3916
#define C99_LIMIT_MACRO_3917 3917
#define C99_LIMIT_MACRO_3918 3918
#define C99_LIMIT_MACRO_3919 3919
#define C99_LIMIT_MACRO_3920 3920
#define C99_LIMIT_MACRO_3921 3921
#define C99_LIMIT_MACRO_3922 3922
#define C99_LIMIT_MACRO_3923 3923
#define C99_LIMIT_MACRO_3924 3924
#define C99_LIMIT_MACRO_3925 3925
#define C99_LIMIT_MACRO_3926 3926
#define C99_LIMIT_MACRO_3927 3927
#define C99_LIMIT_MACRO_3928 3928
#define C99_LIMIT_MACRO_3929 3929
#define C99_LIMIT_MACRO_3930 3930
#define C99_LIMIT_MACRO_3931 3931
#define C99_LIMIT_MACRO_3932 3932
#define C99_LIMIT_MACRO_3933 3933
#define C99_LIMIT_MACRO_3934 3934
#define C99_LIMIT_MACRO_3935 3935
#define C99_LIMIT_MACRO_3936 3936
#define C99_LIMIT_MACRO_3937 3937
#define C99_LIMIT_MACRO_3938 3938
#define C99_LIMIT_MACRO_3939 3939
#define C99_LIMIT_MACRO_3940 3940
#define C99_LIMIT_MACRO_3941 3941
#define C99_LIMIT_MACRO_3942 3942
#define C99_LIMIT_MACRO_3943 3943
#define C99_LIMIT_MACRO_3944 3944
#define C99_LIMIT_MACRO_3945 3945
#define C99_LIMIT_MACRO_3946 3946
#define C99_LIMIT_MACRO_3947 3947
#define C99_LIMIT_MACRO_3948 3948
#define C99_LIMIT_MACRO_3949 3949
#define C99_LIMIT_MACRO_3950 3950
#define C99_LIMIT_MACRO_3951 3951
#define C99_LIMIT_MACRO_3952 3952
#define C99_LIMIT_MACRO_3953 3953
#define C99_LIMIT_MACRO_3954 3954
#define C99_LIMIT_MACRO_3955 3955
#define C99_LIMIT_MACRO_3956 3956
#define C99_LIMIT_MACRO_3957 3957
#define C99_LIMIT_MACRO_3958 3958
#define C99_LIMIT_MACRO_3959 3959
#define C99_LIMIT_MACRO_3960 3960
#define C99_LIMIT_MACRO_3961 3961
#define C99_LIMIT_MACRO_3962 3962
#define C99_LIMIT_MACRO_3963 3963
#define C99_LIMIT_MACRO_3964 3964
#define C99_LIMIT_MACRO_3965 3965
#define C99_LIMIT_MACRO_3966 3966
#define C99_LIMIT_MACRO_3967 3967
#define C99_LIMIT_MACRO_3968 3968
#define C99_LIMIT_MACRO_3969 3969
#define C99_LIMIT_MACRO_3970 3970
#define C99_LIMIT_MACRO_3971 3971
#define C99_LIMIT_MACRO_3972 3972
#define C99_LIMIT_MACRO_3973 3973
#define C99_LIMIT_MACRO_3974 3974
#define C99_LIMIT_MACRO_3975 3975
#define C99_LIMIT_MACRO_3976 3976
#define C99_LIMIT_MACRO_3977 3977
#define C99_LIMIT_MACRO_3978 3978
#define C99_LIMIT_MACRO_3979 3979
#define C99_LIMIT_MACRO_3980 3980
#define C99_LIMIT_MACRO_3981 3981
#define C99_LIMIT_MACRO_3982 3982
#define C99_LIMIT_MACRO_3983 3983
#define C99_LIMIT_MACRO_3984 3984
#define C99_LIMIT_MACRO_3985 3985
#define C99_LIMIT_MACRO_3986 3986
#define C99_LIMIT_MACRO_3987 3987
#define C99_LIMIT_MACRO_3988 3988
#define C99_LIMIT_MACRO_3989 3989
#define C99_LIMIT_MACRO_3990 3990
#define C99_LIMIT_MACRO_3991 3991
#define C99_LIMIT_MACRO_3992 3992
#define C99_LIMIT_MACRO_3993 3993
#define C99_LIMIT_MACRO_3994 3994
#define C99_LIMIT_MACRO_3995 3995
#define C99_LIMIT_MACRO_3996 3996
#define C99_LIMIT_MACRO_3997 3997
#define C99_LIMIT_MACRO_3998 3998
#define C99_LIMIT_MACRO_3999 3999
#define C99_LIMIT_MACRO_4000 4000
#define C99_LIMIT_MACRO_4001 4001
#define C99_LIMIT_MACRO_4002 4002
#define C99_LIMIT_MACRO_4003 4003
#define C99_LIMIT_MACRO_4004 4004
#define C99_LIMIT_MACRO_4005 4005
#define C99_LIMIT_MACRO_4006 4006
#define C99_LIMIT_MACRO_4007 4007
#define C99_LIMIT_MACRO_4008 4008
#define C99_LIMIT_MACRO_4009 4009
#define C99_LIMIT_MACRO_4010 4010
#define C99_LIMIT_MACRO_4011 4011
#define C99_LIMIT_MACRO_4012 4012
#define C99_LIMIT_MACRO_4013 4013
#define C99_LIMIT_MACRO_4014 4014
#define C99_LIMIT_MACRO_4015 4015
#define C99_LIMIT_MACRO_4016 4016
#define C99_LIMIT_MACRO_4017 4017
#define C99_LIMIT_MACRO_4018 4018
#define C99_LIMIT_MACRO_4019 4019
#define C99_LIMIT_MACRO_4020 4020
#define C99_LIMIT_MACRO_4021 4021
#define C99_LIMIT_MACRO_4022 4022
#define C99_LIMIT_MACRO_4023 4023
#define C99_LIMIT_MACRO_4024 4024
#define C99_LIMIT_MACRO_4025 4025
#define C99_LIMIT_MACRO_4026 4026
#define C99_LIMIT_MACRO_4027 4027
#define C99_LIMIT_MACRO_4028 4028
#define C99_LIMIT_MACRO_4029 4029
#define C99_LIMIT_MACRO_4030 4030
#define C99_LIMIT_MACRO_4031 4031
#define C99_LIMIT_MACRO_4032 4032
#define C99_LIMIT_MACRO_4033 4033
#define C99_LIMIT_MACRO_4034 4034
#define C99_LIMIT_MACRO_4035 4035
#define C99_LIMIT_MACRO_4036 4036
#define C99_LIMIT_MACRO_4037 4037
#define C99_LIMIT_MACRO_4038 4038
#define C99_LIMIT_MACRO_4039 4039
#define C99_LIMIT_MACRO_4040 4040
#define C99_LIMIT_MACRO_4041 4041
#define C99_LIMIT_MACRO_4042 4042
#define C99_LIMIT_MACRO_4043 4043
#define C99_LIMIT_MACRO_4044 4044
#define C99_LIMIT_MACRO_4045 4045
#define C99_LIMIT_MACRO_4046 4046
#define C99_LIMIT_MACRO_4047 4047
#define C99_LIMIT_MACRO_4048 4048
#define C99_LIMIT_MACRO_4049 4049
#define C99_LIMIT_MACRO_4050 4050
#define C99_LIMIT_MACRO_4051 4051
#define C99_LIMIT_MACRO_4052 4052
#define C99_LIMIT_MACRO_4053 4053
#define C99_LIMIT_MACRO_4054 4054
#define C99_LIMIT_MACRO_4055 4055
#define C99_LIMIT_MACRO_4056 4056
#define C99_LIMIT_MACRO_4057 4057
#define C99_LIMIT_MACRO_4058 4058
#define C99_LIMIT_MACRO_4059 4059
#define C99_LIMIT_MACRO_4060 4060
#define C99_LIMIT_MACRO_4061 4061
#define C99_LIMIT_MACRO_4062 4062
#define C99_LIMIT_MACRO_4063 4063
#define C99_LIMIT_MACRO_4064 4064
#define C99_LIMIT_MACRO_4065 4065
#define C99_LIMIT_MACRO_4066 4066
#define C99_LIMIT_MACRO_4067 4067
#define C99_LIMIT_MACRO_4068 4068
#define C99_LIMIT_MACRO_4069 4069
#define C99_LIMIT_MACRO_4070 4070
#define C99_LIMIT_MACRO_4071 4071
#define C99_LIMIT_MACRO_4072 4072
#define C99_LIMIT_MACRO_4073 4073
#define C99_LIMIT_MACRO_4074 4074
#define C99_LIMIT_MACRO_4075 4075
#define C99_LIMIT_MACRO_4076 4076
#define C99_LIMIT_MACRO_4077 4077
#define C99_LIMIT_MACRO_4078 4078
#define C99_LIMIT_MACRO_4079 4079
#define C99_LIMIT_MACRO_4080 4080
#define C99_LIMIT_MACRO_4081 4081
#define C99_LIMIT_MACRO_4082 4082
#define C99_LIMIT_MACRO_4083 4083
#define C99_LIMIT_MACRO_4084 4084
#define C99_LIMIT_MACRO_4085 4085
#define C99_LIMIT_MACRO_4086 4086
#define C99_LIMIT_MACRO_4087 4087
#define C99_LIMIT_MACRO_4088 4088
#define C99_LIMIT_MACRO_4089 4089
#define C99_LIMIT_MACRO_4090 4090
#define C99_LIMIT_MACRO_4091 4091
#define C99_LIMIT_MACRO_4092 4092
#define C99_LIMIT_MACRO_4093 4093
#define C99_LIMIT_MACRO_4094 4094

/* A logical source line of at least 4095 characters (one comment line). */
/* xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx */
/* The same, built from backslash-continued physical lines. */
/* yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy\
   yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy\
   yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy\
   yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy\
   yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy */

/* A string literal of exactly 4095 characters (the C99 minimum an
 * implementation must support), and the same length reached by
 * concatenating 15 literals of 273 characters each. */
static const char c99_long_literal[] =
    "012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234";
static const char c99_long_concatenated[] =
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxy"
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxy"
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxy"
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxy"
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxy"
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxy"
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxy"
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxy"
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxy"
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxy"
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxy"
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxy"
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxy"
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxy"
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxy";

/* Longer than the guaranteed minimum: these compile on GCC and Clang but
 * trip -Woverlength-strings (part of -Wpedantic), so build with
 * -Wno-overlength-strings to enable them. */
#ifdef C99_OVERLONG_STRINGS
static const char c99_overlong_literal[] =
    "01234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789";
static const char c99_overlong_concatenated[] =
    "abcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghij"
    "abcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghij"
    "abcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghij"
    "abcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghij"
    "abcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghij"
    "abcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghij"
    "abcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghij"
    "abcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghij"
    "abcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghij"
    "abcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghij"
    "abcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghij"
    "abcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghij";
#endif
/* 32767 bytes in one object. */
static unsigned char c99_large_object[40000];

/* 63 significant characters in an internal identifier: these two agree for
 * 63 characters and diverge only afterwards, so they must stay distinct. */
static int c99_internal_identifier_name_of_exactly_sixty_three_chars_abcde_one = 11;
static int c99_internal_identifier_name_of_exactly_sixty_three_chars_abcde_two = 22;

/* 63 levels of nested parentheses within a subexpression. */
static int c99_deep_parens(void)
{
    int v = (((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((42)))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))));
    return v;
}

/* 127 nesting levels of blocks. */
static int c99_deep_blocks(void)
{
    int depth = 0;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    { depth++;
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    return depth;
}

/* 63 levels of nested conditional inclusion. */
static int c99_nested_conditional(void)
{
    int n = 0;
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#define C99_PP_NESTING_LEVEL 63
    n = C99_PP_NESTING_LEVEL;
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
    return n;
}

/* 127 parameters in one function definition and 127 arguments in one call. */
static long long c99_many_params(long long p001, long long p002, long long p003, long long p004, long long p005, long long p006, long long p007, long long p008, long long p009, long long p010, long long p011, long long p012, long long p013, long long p014, long long p015, long long p016, long long p017, long long p018, long long p019, long long p020, long long p021, long long p022, long long p023, long long p024, long long p025, long long p026, long long p027, long long p028, long long p029, long long p030, long long p031, long long p032, long long p033, long long p034, long long p035, long long p036, long long p037, long long p038, long long p039, long long p040, long long p041, long long p042, long long p043, long long p044, long long p045, long long p046, long long p047, long long p048, long long p049, long long p050, long long p051, long long p052, long long p053, long long p054, long long p055, long long p056, long long p057, long long p058, long long p059, long long p060, long long p061, long long p062, long long p063, long long p064, long long p065, long long p066, long long p067, long long p068, long long p069, long long p070, long long p071, long long p072, long long p073, long long p074, long long p075, long long p076, long long p077, long long p078, long long p079, long long p080, long long p081, long long p082, long long p083, long long p084, long long p085, long long p086, long long p087, long long p088, long long p089, long long p090, long long p091, long long p092, long long p093, long long p094, long long p095, long long p096, long long p097, long long p098, long long p099, long long p100, long long p101, long long p102, long long p103, long long p104, long long p105, long long p106, long long p107, long long p108, long long p109, long long p110, long long p111, long long p112, long long p113, long long p114, long long p115, long long p116, long long p117, long long p118, long long p119, long long p120, long long p121, long long p122, long long p123, long long p124, long long p125, long long p126, long long p127)
{
    return p001 + p002 + p003 + p004 + p005 + p006 + p007 + p008 + p009 + p010 + p011 + p012 + p013 + p014 + p015 + p016 + p017 + p018 + p019 + p020 + p021 + p022 + p023 + p024 + p025 + p026 + p027 + p028 + p029 + p030 + p031 + p032 + p033 + p034 + p035 + p036 + p037 + p038 + p039 + p040 + p041 + p042 + p043 + p044 + p045 + p046 + p047 + p048 + p049 + p050 + p051 + p052 + p053 + p054 + p055 + p056 + p057 + p058 + p059 + p060 + p061 + p062 + p063 + p064 + p065 + p066 + p067 + p068 + p069 + p070 + p071 + p072 + p073 + p074 + p075 + p076 + p077 + p078 + p079 + p080 + p081 + p082 + p083 + p084 + p085 + p086 + p087 + p088 + p089 + p090 + p091 + p092 + p093 + p094 + p095 + p096 + p097 + p098 + p099 + p100 + p101 + p102 + p103 + p104 + p105 + p106 + p107 + p108 + p109 + p110 + p111 + p112 + p113 + p114 + p115 + p116 + p117 + p118 + p119 + p120 + p121 + p122 + p123 + p124 + p125 + p126 + p127;
}
static long long c99_call_many_params(void)
{
    return c99_many_params(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127);
}

/* 12 pointer declarators modifying one arithmetic type. */
static int c99_twelve_level_pointer(void)
{
    int value = 5;
    int *p01 = &value;
    int **p02 = &p01;
    int ***p03 = &p02;
    int ****p04 = &p03;
    int *****p05 = &p04;
    int ******p06 = &p05;
    int *******p07 = &p06;
    int ********p08 = &p07;
    int *********p09 = &p08;
    int **********p10 = &p09;
    int ***********p11 = &p10;
    int ************p12 = &p11;
    return ************p12;
}

/* 511 identifiers with block scope declared in one block. */
static int c99_many_block_identifiers(void)
{
    int b000 = 0;
    int b001 = 1;
    int b002 = 2;
    int b003 = 3;
    int b004 = 4;
    int b005 = 5;
    int b006 = 6;
    int b007 = 7;
    int b008 = 8;
    int b009 = 9;
    int b010 = 10;
    int b011 = 11;
    int b012 = 12;
    int b013 = 13;
    int b014 = 14;
    int b015 = 15;
    int b016 = 16;
    int b017 = 17;
    int b018 = 18;
    int b019 = 19;
    int b020 = 20;
    int b021 = 21;
    int b022 = 22;
    int b023 = 23;
    int b024 = 24;
    int b025 = 25;
    int b026 = 26;
    int b027 = 27;
    int b028 = 28;
    int b029 = 29;
    int b030 = 30;
    int b031 = 31;
    int b032 = 32;
    int b033 = 33;
    int b034 = 34;
    int b035 = 35;
    int b036 = 36;
    int b037 = 37;
    int b038 = 38;
    int b039 = 39;
    int b040 = 40;
    int b041 = 41;
    int b042 = 42;
    int b043 = 43;
    int b044 = 44;
    int b045 = 45;
    int b046 = 46;
    int b047 = 47;
    int b048 = 48;
    int b049 = 49;
    int b050 = 50;
    int b051 = 51;
    int b052 = 52;
    int b053 = 53;
    int b054 = 54;
    int b055 = 55;
    int b056 = 56;
    int b057 = 57;
    int b058 = 58;
    int b059 = 59;
    int b060 = 60;
    int b061 = 61;
    int b062 = 62;
    int b063 = 63;
    int b064 = 64;
    int b065 = 65;
    int b066 = 66;
    int b067 = 67;
    int b068 = 68;
    int b069 = 69;
    int b070 = 70;
    int b071 = 71;
    int b072 = 72;
    int b073 = 73;
    int b074 = 74;
    int b075 = 75;
    int b076 = 76;
    int b077 = 77;
    int b078 = 78;
    int b079 = 79;
    int b080 = 80;
    int b081 = 81;
    int b082 = 82;
    int b083 = 83;
    int b084 = 84;
    int b085 = 85;
    int b086 = 86;
    int b087 = 87;
    int b088 = 88;
    int b089 = 89;
    int b090 = 90;
    int b091 = 91;
    int b092 = 92;
    int b093 = 93;
    int b094 = 94;
    int b095 = 95;
    int b096 = 96;
    int b097 = 97;
    int b098 = 98;
    int b099 = 99;
    int b100 = 100;
    int b101 = 101;
    int b102 = 102;
    int b103 = 103;
    int b104 = 104;
    int b105 = 105;
    int b106 = 106;
    int b107 = 107;
    int b108 = 108;
    int b109 = 109;
    int b110 = 110;
    int b111 = 111;
    int b112 = 112;
    int b113 = 113;
    int b114 = 114;
    int b115 = 115;
    int b116 = 116;
    int b117 = 117;
    int b118 = 118;
    int b119 = 119;
    int b120 = 120;
    int b121 = 121;
    int b122 = 122;
    int b123 = 123;
    int b124 = 124;
    int b125 = 125;
    int b126 = 126;
    int b127 = 127;
    int b128 = 128;
    int b129 = 129;
    int b130 = 130;
    int b131 = 131;
    int b132 = 132;
    int b133 = 133;
    int b134 = 134;
    int b135 = 135;
    int b136 = 136;
    int b137 = 137;
    int b138 = 138;
    int b139 = 139;
    int b140 = 140;
    int b141 = 141;
    int b142 = 142;
    int b143 = 143;
    int b144 = 144;
    int b145 = 145;
    int b146 = 146;
    int b147 = 147;
    int b148 = 148;
    int b149 = 149;
    int b150 = 150;
    int b151 = 151;
    int b152 = 152;
    int b153 = 153;
    int b154 = 154;
    int b155 = 155;
    int b156 = 156;
    int b157 = 157;
    int b158 = 158;
    int b159 = 159;
    int b160 = 160;
    int b161 = 161;
    int b162 = 162;
    int b163 = 163;
    int b164 = 164;
    int b165 = 165;
    int b166 = 166;
    int b167 = 167;
    int b168 = 168;
    int b169 = 169;
    int b170 = 170;
    int b171 = 171;
    int b172 = 172;
    int b173 = 173;
    int b174 = 174;
    int b175 = 175;
    int b176 = 176;
    int b177 = 177;
    int b178 = 178;
    int b179 = 179;
    int b180 = 180;
    int b181 = 181;
    int b182 = 182;
    int b183 = 183;
    int b184 = 184;
    int b185 = 185;
    int b186 = 186;
    int b187 = 187;
    int b188 = 188;
    int b189 = 189;
    int b190 = 190;
    int b191 = 191;
    int b192 = 192;
    int b193 = 193;
    int b194 = 194;
    int b195 = 195;
    int b196 = 196;
    int b197 = 197;
    int b198 = 198;
    int b199 = 199;
    int b200 = 200;
    int b201 = 201;
    int b202 = 202;
    int b203 = 203;
    int b204 = 204;
    int b205 = 205;
    int b206 = 206;
    int b207 = 207;
    int b208 = 208;
    int b209 = 209;
    int b210 = 210;
    int b211 = 211;
    int b212 = 212;
    int b213 = 213;
    int b214 = 214;
    int b215 = 215;
    int b216 = 216;
    int b217 = 217;
    int b218 = 218;
    int b219 = 219;
    int b220 = 220;
    int b221 = 221;
    int b222 = 222;
    int b223 = 223;
    int b224 = 224;
    int b225 = 225;
    int b226 = 226;
    int b227 = 227;
    int b228 = 228;
    int b229 = 229;
    int b230 = 230;
    int b231 = 231;
    int b232 = 232;
    int b233 = 233;
    int b234 = 234;
    int b235 = 235;
    int b236 = 236;
    int b237 = 237;
    int b238 = 238;
    int b239 = 239;
    int b240 = 240;
    int b241 = 241;
    int b242 = 242;
    int b243 = 243;
    int b244 = 244;
    int b245 = 245;
    int b246 = 246;
    int b247 = 247;
    int b248 = 248;
    int b249 = 249;
    int b250 = 250;
    int b251 = 251;
    int b252 = 252;
    int b253 = 253;
    int b254 = 254;
    int b255 = 255;
    int b256 = 256;
    int b257 = 257;
    int b258 = 258;
    int b259 = 259;
    int b260 = 260;
    int b261 = 261;
    int b262 = 262;
    int b263 = 263;
    int b264 = 264;
    int b265 = 265;
    int b266 = 266;
    int b267 = 267;
    int b268 = 268;
    int b269 = 269;
    int b270 = 270;
    int b271 = 271;
    int b272 = 272;
    int b273 = 273;
    int b274 = 274;
    int b275 = 275;
    int b276 = 276;
    int b277 = 277;
    int b278 = 278;
    int b279 = 279;
    int b280 = 280;
    int b281 = 281;
    int b282 = 282;
    int b283 = 283;
    int b284 = 284;
    int b285 = 285;
    int b286 = 286;
    int b287 = 287;
    int b288 = 288;
    int b289 = 289;
    int b290 = 290;
    int b291 = 291;
    int b292 = 292;
    int b293 = 293;
    int b294 = 294;
    int b295 = 295;
    int b296 = 296;
    int b297 = 297;
    int b298 = 298;
    int b299 = 299;
    int b300 = 300;
    int b301 = 301;
    int b302 = 302;
    int b303 = 303;
    int b304 = 304;
    int b305 = 305;
    int b306 = 306;
    int b307 = 307;
    int b308 = 308;
    int b309 = 309;
    int b310 = 310;
    int b311 = 311;
    int b312 = 312;
    int b313 = 313;
    int b314 = 314;
    int b315 = 315;
    int b316 = 316;
    int b317 = 317;
    int b318 = 318;
    int b319 = 319;
    int b320 = 320;
    int b321 = 321;
    int b322 = 322;
    int b323 = 323;
    int b324 = 324;
    int b325 = 325;
    int b326 = 326;
    int b327 = 327;
    int b328 = 328;
    int b329 = 329;
    int b330 = 330;
    int b331 = 331;
    int b332 = 332;
    int b333 = 333;
    int b334 = 334;
    int b335 = 335;
    int b336 = 336;
    int b337 = 337;
    int b338 = 338;
    int b339 = 339;
    int b340 = 340;
    int b341 = 341;
    int b342 = 342;
    int b343 = 343;
    int b344 = 344;
    int b345 = 345;
    int b346 = 346;
    int b347 = 347;
    int b348 = 348;
    int b349 = 349;
    int b350 = 350;
    int b351 = 351;
    int b352 = 352;
    int b353 = 353;
    int b354 = 354;
    int b355 = 355;
    int b356 = 356;
    int b357 = 357;
    int b358 = 358;
    int b359 = 359;
    int b360 = 360;
    int b361 = 361;
    int b362 = 362;
    int b363 = 363;
    int b364 = 364;
    int b365 = 365;
    int b366 = 366;
    int b367 = 367;
    int b368 = 368;
    int b369 = 369;
    int b370 = 370;
    int b371 = 371;
    int b372 = 372;
    int b373 = 373;
    int b374 = 374;
    int b375 = 375;
    int b376 = 376;
    int b377 = 377;
    int b378 = 378;
    int b379 = 379;
    int b380 = 380;
    int b381 = 381;
    int b382 = 382;
    int b383 = 383;
    int b384 = 384;
    int b385 = 385;
    int b386 = 386;
    int b387 = 387;
    int b388 = 388;
    int b389 = 389;
    int b390 = 390;
    int b391 = 391;
    int b392 = 392;
    int b393 = 393;
    int b394 = 394;
    int b395 = 395;
    int b396 = 396;
    int b397 = 397;
    int b398 = 398;
    int b399 = 399;
    int b400 = 400;
    int b401 = 401;
    int b402 = 402;
    int b403 = 403;
    int b404 = 404;
    int b405 = 405;
    int b406 = 406;
    int b407 = 407;
    int b408 = 408;
    int b409 = 409;
    int b410 = 410;
    int b411 = 411;
    int b412 = 412;
    int b413 = 413;
    int b414 = 414;
    int b415 = 415;
    int b416 = 416;
    int b417 = 417;
    int b418 = 418;
    int b419 = 419;
    int b420 = 420;
    int b421 = 421;
    int b422 = 422;
    int b423 = 423;
    int b424 = 424;
    int b425 = 425;
    int b426 = 426;
    int b427 = 427;
    int b428 = 428;
    int b429 = 429;
    int b430 = 430;
    int b431 = 431;
    int b432 = 432;
    int b433 = 433;
    int b434 = 434;
    int b435 = 435;
    int b436 = 436;
    int b437 = 437;
    int b438 = 438;
    int b439 = 439;
    int b440 = 440;
    int b441 = 441;
    int b442 = 442;
    int b443 = 443;
    int b444 = 444;
    int b445 = 445;
    int b446 = 446;
    int b447 = 447;
    int b448 = 448;
    int b449 = 449;
    int b450 = 450;
    int b451 = 451;
    int b452 = 452;
    int b453 = 453;
    int b454 = 454;
    int b455 = 455;
    int b456 = 456;
    int b457 = 457;
    int b458 = 458;
    int b459 = 459;
    int b460 = 460;
    int b461 = 461;
    int b462 = 462;
    int b463 = 463;
    int b464 = 464;
    int b465 = 465;
    int b466 = 466;
    int b467 = 467;
    int b468 = 468;
    int b469 = 469;
    int b470 = 470;
    int b471 = 471;
    int b472 = 472;
    int b473 = 473;
    int b474 = 474;
    int b475 = 475;
    int b476 = 476;
    int b477 = 477;
    int b478 = 478;
    int b479 = 479;
    int b480 = 480;
    int b481 = 481;
    int b482 = 482;
    int b483 = 483;
    int b484 = 484;
    int b485 = 485;
    int b486 = 486;
    int b487 = 487;
    int b488 = 488;
    int b489 = 489;
    int b490 = 490;
    int b491 = 491;
    int b492 = 492;
    int b493 = 493;
    int b494 = 494;
    int b495 = 495;
    int b496 = 496;
    int b497 = 497;
    int b498 = 498;
    int b499 = 499;
    int b500 = 500;
    int b501 = 501;
    int b502 = 502;
    int b503 = 503;
    int b504 = 504;
    int b505 = 505;
    int b506 = 506;
    int b507 = 507;
    int b508 = 508;
    int b509 = 509;
    int b510 = 510;
    int total = 0;
    total += b000 + b001 + b002 + b003 + b004 + b005 + b006 + b007 + b008 + b009 + b010 + b011 + b012 + b013 + b014 + b015 + b016 + b017 + b018 + b019 + b020 + b021 + b022 + b023 + b024 + b025 + b026 + b027 + b028 + b029 + b030 + b031 + b032 + b033 + b034 + b035 + b036 + b037 + b038 + b039 + b040 + b041 + b042 + b043 + b044 + b045 + b046 + b047 + b048 + b049 + b050 + b051 + b052 + b053 + b054 + b055 + b056 + b057 + b058 + b059 + b060 + b061 + b062 + b063 + b064 + b065 + b066 + b067 + b068 + b069 + b070 + b071 + b072 + b073 + b074 + b075 + b076 + b077 + b078 + b079 + b080 + b081 + b082 + b083 + b084 + b085 + b086 + b087 + b088 + b089 + b090 + b091 + b092 + b093 + b094 + b095 + b096 + b097 + b098 + b099 + b100 + b101 + b102 + b103 + b104 + b105 + b106 + b107 + b108 + b109 + b110 + b111 + b112 + b113 + b114 + b115 + b116 + b117 + b118 + b119 + b120 + b121 + b122 + b123 + b124 + b125 + b126 + b127 + b128 + b129 + b130 + b131 + b132 + b133 + b134 + b135 + b136 + b137 + b138 + b139 + b140 + b141 + b142 + b143 + b144 + b145 + b146 + b147 + b148 + b149 + b150 + b151 + b152 + b153 + b154 + b155 + b156 + b157 + b158 + b159 + b160 + b161 + b162 + b163 + b164 + b165 + b166 + b167 + b168 + b169 + b170 + b171 + b172 + b173 + b174 + b175 + b176 + b177 + b178 + b179 + b180 + b181 + b182 + b183 + b184 + b185 + b186 + b187 + b188 + b189 + b190 + b191 + b192 + b193 + b194 + b195 + b196 + b197 + b198 + b199 + b200 + b201 + b202 + b203 + b204 + b205 + b206 + b207 + b208 + b209 + b210 + b211 + b212 + b213 + b214 + b215 + b216 + b217 + b218 + b219 + b220 + b221 + b222 + b223 + b224 + b225 + b226 + b227 + b228 + b229 + b230 + b231 + b232 + b233 + b234 + b235 + b236 + b237 + b238 + b239 + b240 + b241 + b242 + b243 + b244 + b245 + b246 + b247 + b248 + b249 + b250 + b251 + b252 + b253 + b254 + b255 + b256 + b257 + b258 + b259 + b260 + b261 + b262 + b263 + b264 + b265 + b266 + b267 + b268 + b269 + b270 + b271 + b272 + b273 + b274 + b275 + b276 + b277 + b278 + b279 + b280 + b281 + b282 + b283 + b284 + b285 + b286 + b287 + b288 + b289 + b290 + b291 + b292 + b293 + b294 + b295 + b296 + b297 + b298 + b299 + b300 + b301 + b302 + b303 + b304 + b305 + b306 + b307 + b308 + b309 + b310 + b311 + b312 + b313 + b314 + b315 + b316 + b317 + b318 + b319 + b320 + b321 + b322 + b323 + b324 + b325 + b326 + b327 + b328 + b329 + b330 + b331 + b332 + b333 + b334 + b335 + b336 + b337 + b338 + b339 + b340 + b341 + b342 + b343 + b344 + b345 + b346 + b347 + b348 + b349 + b350 + b351 + b352 + b353 + b354 + b355 + b356 + b357 + b358 + b359 + b360 + b361 + b362 + b363 + b364 + b365 + b366 + b367 + b368 + b369 + b370 + b371 + b372 + b373 + b374 + b375 + b376 + b377 + b378 + b379 + b380 + b381 + b382 + b383 + b384 + b385 + b386 + b387 + b388 + b389 + b390 + b391 + b392 + b393 + b394 + b395 + b396 + b397 + b398 + b399 + b400 + b401 + b402 + b403 + b404 + b405 + b406 + b407 + b408 + b409 + b410 + b411 + b412 + b413 + b414 + b415 + b416 + b417 + b418 + b419 + b420 + b421 + b422 + b423 + b424 + b425 + b426 + b427 + b428 + b429 + b430 + b431 + b432 + b433 + b434 + b435 + b436 + b437 + b438 + b439 + b440 + b441 + b442 + b443 + b444 + b445 + b446 + b447 + b448 + b449 + b450 + b451 + b452 + b453 + b454 + b455 + b456 + b457 + b458 + b459 + b460 + b461 + b462 + b463 + b464 + b465 + b466 + b467 + b468 + b469 + b470 + b471 + b472 + b473 + b474 + b475 + b476 + b477 + b478 + b479 + b480 + b481 + b482 + b483 + b484 + b485 + b486 + b487 + b488 + b489 + b490 + b491 + b492 + b493 + b494 + b495 + b496 + b497 + b498 + b499 + b500 + b501 + b502 + b503 + b504 + b505 + b506 + b507 + b508 + b509 + b510;
    return total;
}

/* 1023 members in one structure. */
struct c99_wide_struct {
    int m0000;
    int m0001;
    int m0002;
    int m0003;
    int m0004;
    int m0005;
    int m0006;
    int m0007;
    int m0008;
    int m0009;
    int m0010;
    int m0011;
    int m0012;
    int m0013;
    int m0014;
    int m0015;
    int m0016;
    int m0017;
    int m0018;
    int m0019;
    int m0020;
    int m0021;
    int m0022;
    int m0023;
    int m0024;
    int m0025;
    int m0026;
    int m0027;
    int m0028;
    int m0029;
    int m0030;
    int m0031;
    int m0032;
    int m0033;
    int m0034;
    int m0035;
    int m0036;
    int m0037;
    int m0038;
    int m0039;
    int m0040;
    int m0041;
    int m0042;
    int m0043;
    int m0044;
    int m0045;
    int m0046;
    int m0047;
    int m0048;
    int m0049;
    int m0050;
    int m0051;
    int m0052;
    int m0053;
    int m0054;
    int m0055;
    int m0056;
    int m0057;
    int m0058;
    int m0059;
    int m0060;
    int m0061;
    int m0062;
    int m0063;
    int m0064;
    int m0065;
    int m0066;
    int m0067;
    int m0068;
    int m0069;
    int m0070;
    int m0071;
    int m0072;
    int m0073;
    int m0074;
    int m0075;
    int m0076;
    int m0077;
    int m0078;
    int m0079;
    int m0080;
    int m0081;
    int m0082;
    int m0083;
    int m0084;
    int m0085;
    int m0086;
    int m0087;
    int m0088;
    int m0089;
    int m0090;
    int m0091;
    int m0092;
    int m0093;
    int m0094;
    int m0095;
    int m0096;
    int m0097;
    int m0098;
    int m0099;
    int m0100;
    int m0101;
    int m0102;
    int m0103;
    int m0104;
    int m0105;
    int m0106;
    int m0107;
    int m0108;
    int m0109;
    int m0110;
    int m0111;
    int m0112;
    int m0113;
    int m0114;
    int m0115;
    int m0116;
    int m0117;
    int m0118;
    int m0119;
    int m0120;
    int m0121;
    int m0122;
    int m0123;
    int m0124;
    int m0125;
    int m0126;
    int m0127;
    int m0128;
    int m0129;
    int m0130;
    int m0131;
    int m0132;
    int m0133;
    int m0134;
    int m0135;
    int m0136;
    int m0137;
    int m0138;
    int m0139;
    int m0140;
    int m0141;
    int m0142;
    int m0143;
    int m0144;
    int m0145;
    int m0146;
    int m0147;
    int m0148;
    int m0149;
    int m0150;
    int m0151;
    int m0152;
    int m0153;
    int m0154;
    int m0155;
    int m0156;
    int m0157;
    int m0158;
    int m0159;
    int m0160;
    int m0161;
    int m0162;
    int m0163;
    int m0164;
    int m0165;
    int m0166;
    int m0167;
    int m0168;
    int m0169;
    int m0170;
    int m0171;
    int m0172;
    int m0173;
    int m0174;
    int m0175;
    int m0176;
    int m0177;
    int m0178;
    int m0179;
    int m0180;
    int m0181;
    int m0182;
    int m0183;
    int m0184;
    int m0185;
    int m0186;
    int m0187;
    int m0188;
    int m0189;
    int m0190;
    int m0191;
    int m0192;
    int m0193;
    int m0194;
    int m0195;
    int m0196;
    int m0197;
    int m0198;
    int m0199;
    int m0200;
    int m0201;
    int m0202;
    int m0203;
    int m0204;
    int m0205;
    int m0206;
    int m0207;
    int m0208;
    int m0209;
    int m0210;
    int m0211;
    int m0212;
    int m0213;
    int m0214;
    int m0215;
    int m0216;
    int m0217;
    int m0218;
    int m0219;
    int m0220;
    int m0221;
    int m0222;
    int m0223;
    int m0224;
    int m0225;
    int m0226;
    int m0227;
    int m0228;
    int m0229;
    int m0230;
    int m0231;
    int m0232;
    int m0233;
    int m0234;
    int m0235;
    int m0236;
    int m0237;
    int m0238;
    int m0239;
    int m0240;
    int m0241;
    int m0242;
    int m0243;
    int m0244;
    int m0245;
    int m0246;
    int m0247;
    int m0248;
    int m0249;
    int m0250;
    int m0251;
    int m0252;
    int m0253;
    int m0254;
    int m0255;
    int m0256;
    int m0257;
    int m0258;
    int m0259;
    int m0260;
    int m0261;
    int m0262;
    int m0263;
    int m0264;
    int m0265;
    int m0266;
    int m0267;
    int m0268;
    int m0269;
    int m0270;
    int m0271;
    int m0272;
    int m0273;
    int m0274;
    int m0275;
    int m0276;
    int m0277;
    int m0278;
    int m0279;
    int m0280;
    int m0281;
    int m0282;
    int m0283;
    int m0284;
    int m0285;
    int m0286;
    int m0287;
    int m0288;
    int m0289;
    int m0290;
    int m0291;
    int m0292;
    int m0293;
    int m0294;
    int m0295;
    int m0296;
    int m0297;
    int m0298;
    int m0299;
    int m0300;
    int m0301;
    int m0302;
    int m0303;
    int m0304;
    int m0305;
    int m0306;
    int m0307;
    int m0308;
    int m0309;
    int m0310;
    int m0311;
    int m0312;
    int m0313;
    int m0314;
    int m0315;
    int m0316;
    int m0317;
    int m0318;
    int m0319;
    int m0320;
    int m0321;
    int m0322;
    int m0323;
    int m0324;
    int m0325;
    int m0326;
    int m0327;
    int m0328;
    int m0329;
    int m0330;
    int m0331;
    int m0332;
    int m0333;
    int m0334;
    int m0335;
    int m0336;
    int m0337;
    int m0338;
    int m0339;
    int m0340;
    int m0341;
    int m0342;
    int m0343;
    int m0344;
    int m0345;
    int m0346;
    int m0347;
    int m0348;
    int m0349;
    int m0350;
    int m0351;
    int m0352;
    int m0353;
    int m0354;
    int m0355;
    int m0356;
    int m0357;
    int m0358;
    int m0359;
    int m0360;
    int m0361;
    int m0362;
    int m0363;
    int m0364;
    int m0365;
    int m0366;
    int m0367;
    int m0368;
    int m0369;
    int m0370;
    int m0371;
    int m0372;
    int m0373;
    int m0374;
    int m0375;
    int m0376;
    int m0377;
    int m0378;
    int m0379;
    int m0380;
    int m0381;
    int m0382;
    int m0383;
    int m0384;
    int m0385;
    int m0386;
    int m0387;
    int m0388;
    int m0389;
    int m0390;
    int m0391;
    int m0392;
    int m0393;
    int m0394;
    int m0395;
    int m0396;
    int m0397;
    int m0398;
    int m0399;
    int m0400;
    int m0401;
    int m0402;
    int m0403;
    int m0404;
    int m0405;
    int m0406;
    int m0407;
    int m0408;
    int m0409;
    int m0410;
    int m0411;
    int m0412;
    int m0413;
    int m0414;
    int m0415;
    int m0416;
    int m0417;
    int m0418;
    int m0419;
    int m0420;
    int m0421;
    int m0422;
    int m0423;
    int m0424;
    int m0425;
    int m0426;
    int m0427;
    int m0428;
    int m0429;
    int m0430;
    int m0431;
    int m0432;
    int m0433;
    int m0434;
    int m0435;
    int m0436;
    int m0437;
    int m0438;
    int m0439;
    int m0440;
    int m0441;
    int m0442;
    int m0443;
    int m0444;
    int m0445;
    int m0446;
    int m0447;
    int m0448;
    int m0449;
    int m0450;
    int m0451;
    int m0452;
    int m0453;
    int m0454;
    int m0455;
    int m0456;
    int m0457;
    int m0458;
    int m0459;
    int m0460;
    int m0461;
    int m0462;
    int m0463;
    int m0464;
    int m0465;
    int m0466;
    int m0467;
    int m0468;
    int m0469;
    int m0470;
    int m0471;
    int m0472;
    int m0473;
    int m0474;
    int m0475;
    int m0476;
    int m0477;
    int m0478;
    int m0479;
    int m0480;
    int m0481;
    int m0482;
    int m0483;
    int m0484;
    int m0485;
    int m0486;
    int m0487;
    int m0488;
    int m0489;
    int m0490;
    int m0491;
    int m0492;
    int m0493;
    int m0494;
    int m0495;
    int m0496;
    int m0497;
    int m0498;
    int m0499;
    int m0500;
    int m0501;
    int m0502;
    int m0503;
    int m0504;
    int m0505;
    int m0506;
    int m0507;
    int m0508;
    int m0509;
    int m0510;
    int m0511;
    int m0512;
    int m0513;
    int m0514;
    int m0515;
    int m0516;
    int m0517;
    int m0518;
    int m0519;
    int m0520;
    int m0521;
    int m0522;
    int m0523;
    int m0524;
    int m0525;
    int m0526;
    int m0527;
    int m0528;
    int m0529;
    int m0530;
    int m0531;
    int m0532;
    int m0533;
    int m0534;
    int m0535;
    int m0536;
    int m0537;
    int m0538;
    int m0539;
    int m0540;
    int m0541;
    int m0542;
    int m0543;
    int m0544;
    int m0545;
    int m0546;
    int m0547;
    int m0548;
    int m0549;
    int m0550;
    int m0551;
    int m0552;
    int m0553;
    int m0554;
    int m0555;
    int m0556;
    int m0557;
    int m0558;
    int m0559;
    int m0560;
    int m0561;
    int m0562;
    int m0563;
    int m0564;
    int m0565;
    int m0566;
    int m0567;
    int m0568;
    int m0569;
    int m0570;
    int m0571;
    int m0572;
    int m0573;
    int m0574;
    int m0575;
    int m0576;
    int m0577;
    int m0578;
    int m0579;
    int m0580;
    int m0581;
    int m0582;
    int m0583;
    int m0584;
    int m0585;
    int m0586;
    int m0587;
    int m0588;
    int m0589;
    int m0590;
    int m0591;
    int m0592;
    int m0593;
    int m0594;
    int m0595;
    int m0596;
    int m0597;
    int m0598;
    int m0599;
    int m0600;
    int m0601;
    int m0602;
    int m0603;
    int m0604;
    int m0605;
    int m0606;
    int m0607;
    int m0608;
    int m0609;
    int m0610;
    int m0611;
    int m0612;
    int m0613;
    int m0614;
    int m0615;
    int m0616;
    int m0617;
    int m0618;
    int m0619;
    int m0620;
    int m0621;
    int m0622;
    int m0623;
    int m0624;
    int m0625;
    int m0626;
    int m0627;
    int m0628;
    int m0629;
    int m0630;
    int m0631;
    int m0632;
    int m0633;
    int m0634;
    int m0635;
    int m0636;
    int m0637;
    int m0638;
    int m0639;
    int m0640;
    int m0641;
    int m0642;
    int m0643;
    int m0644;
    int m0645;
    int m0646;
    int m0647;
    int m0648;
    int m0649;
    int m0650;
    int m0651;
    int m0652;
    int m0653;
    int m0654;
    int m0655;
    int m0656;
    int m0657;
    int m0658;
    int m0659;
    int m0660;
    int m0661;
    int m0662;
    int m0663;
    int m0664;
    int m0665;
    int m0666;
    int m0667;
    int m0668;
    int m0669;
    int m0670;
    int m0671;
    int m0672;
    int m0673;
    int m0674;
    int m0675;
    int m0676;
    int m0677;
    int m0678;
    int m0679;
    int m0680;
    int m0681;
    int m0682;
    int m0683;
    int m0684;
    int m0685;
    int m0686;
    int m0687;
    int m0688;
    int m0689;
    int m0690;
    int m0691;
    int m0692;
    int m0693;
    int m0694;
    int m0695;
    int m0696;
    int m0697;
    int m0698;
    int m0699;
    int m0700;
    int m0701;
    int m0702;
    int m0703;
    int m0704;
    int m0705;
    int m0706;
    int m0707;
    int m0708;
    int m0709;
    int m0710;
    int m0711;
    int m0712;
    int m0713;
    int m0714;
    int m0715;
    int m0716;
    int m0717;
    int m0718;
    int m0719;
    int m0720;
    int m0721;
    int m0722;
    int m0723;
    int m0724;
    int m0725;
    int m0726;
    int m0727;
    int m0728;
    int m0729;
    int m0730;
    int m0731;
    int m0732;
    int m0733;
    int m0734;
    int m0735;
    int m0736;
    int m0737;
    int m0738;
    int m0739;
    int m0740;
    int m0741;
    int m0742;
    int m0743;
    int m0744;
    int m0745;
    int m0746;
    int m0747;
    int m0748;
    int m0749;
    int m0750;
    int m0751;
    int m0752;
    int m0753;
    int m0754;
    int m0755;
    int m0756;
    int m0757;
    int m0758;
    int m0759;
    int m0760;
    int m0761;
    int m0762;
    int m0763;
    int m0764;
    int m0765;
    int m0766;
    int m0767;
    int m0768;
    int m0769;
    int m0770;
    int m0771;
    int m0772;
    int m0773;
    int m0774;
    int m0775;
    int m0776;
    int m0777;
    int m0778;
    int m0779;
    int m0780;
    int m0781;
    int m0782;
    int m0783;
    int m0784;
    int m0785;
    int m0786;
    int m0787;
    int m0788;
    int m0789;
    int m0790;
    int m0791;
    int m0792;
    int m0793;
    int m0794;
    int m0795;
    int m0796;
    int m0797;
    int m0798;
    int m0799;
    int m0800;
    int m0801;
    int m0802;
    int m0803;
    int m0804;
    int m0805;
    int m0806;
    int m0807;
    int m0808;
    int m0809;
    int m0810;
    int m0811;
    int m0812;
    int m0813;
    int m0814;
    int m0815;
    int m0816;
    int m0817;
    int m0818;
    int m0819;
    int m0820;
    int m0821;
    int m0822;
    int m0823;
    int m0824;
    int m0825;
    int m0826;
    int m0827;
    int m0828;
    int m0829;
    int m0830;
    int m0831;
    int m0832;
    int m0833;
    int m0834;
    int m0835;
    int m0836;
    int m0837;
    int m0838;
    int m0839;
    int m0840;
    int m0841;
    int m0842;
    int m0843;
    int m0844;
    int m0845;
    int m0846;
    int m0847;
    int m0848;
    int m0849;
    int m0850;
    int m0851;
    int m0852;
    int m0853;
    int m0854;
    int m0855;
    int m0856;
    int m0857;
    int m0858;
    int m0859;
    int m0860;
    int m0861;
    int m0862;
    int m0863;
    int m0864;
    int m0865;
    int m0866;
    int m0867;
    int m0868;
    int m0869;
    int m0870;
    int m0871;
    int m0872;
    int m0873;
    int m0874;
    int m0875;
    int m0876;
    int m0877;
    int m0878;
    int m0879;
    int m0880;
    int m0881;
    int m0882;
    int m0883;
    int m0884;
    int m0885;
    int m0886;
    int m0887;
    int m0888;
    int m0889;
    int m0890;
    int m0891;
    int m0892;
    int m0893;
    int m0894;
    int m0895;
    int m0896;
    int m0897;
    int m0898;
    int m0899;
    int m0900;
    int m0901;
    int m0902;
    int m0903;
    int m0904;
    int m0905;
    int m0906;
    int m0907;
    int m0908;
    int m0909;
    int m0910;
    int m0911;
    int m0912;
    int m0913;
    int m0914;
    int m0915;
    int m0916;
    int m0917;
    int m0918;
    int m0919;
    int m0920;
    int m0921;
    int m0922;
    int m0923;
    int m0924;
    int m0925;
    int m0926;
    int m0927;
    int m0928;
    int m0929;
    int m0930;
    int m0931;
    int m0932;
    int m0933;
    int m0934;
    int m0935;
    int m0936;
    int m0937;
    int m0938;
    int m0939;
    int m0940;
    int m0941;
    int m0942;
    int m0943;
    int m0944;
    int m0945;
    int m0946;
    int m0947;
    int m0948;
    int m0949;
    int m0950;
    int m0951;
    int m0952;
    int m0953;
    int m0954;
    int m0955;
    int m0956;
    int m0957;
    int m0958;
    int m0959;
    int m0960;
    int m0961;
    int m0962;
    int m0963;
    int m0964;
    int m0965;
    int m0966;
    int m0967;
    int m0968;
    int m0969;
    int m0970;
    int m0971;
    int m0972;
    int m0973;
    int m0974;
    int m0975;
    int m0976;
    int m0977;
    int m0978;
    int m0979;
    int m0980;
    int m0981;
    int m0982;
    int m0983;
    int m0984;
    int m0985;
    int m0986;
    int m0987;
    int m0988;
    int m0989;
    int m0990;
    int m0991;
    int m0992;
    int m0993;
    int m0994;
    int m0995;
    int m0996;
    int m0997;
    int m0998;
    int m0999;
    int m1000;
    int m1001;
    int m1002;
    int m1003;
    int m1004;
    int m1005;
    int m1006;
    int m1007;
    int m1008;
    int m1009;
    int m1010;
    int m1011;
    int m1012;
    int m1013;
    int m1014;
    int m1015;
    int m1016;
    int m1017;
    int m1018;
    int m1019;
    int m1020;
    int m1021;
    int m1022;
};

/* 1023 members in one union. */
union c99_wide_union {
    int u0000;
    int u0001;
    int u0002;
    int u0003;
    int u0004;
    int u0005;
    int u0006;
    int u0007;
    int u0008;
    int u0009;
    int u0010;
    int u0011;
    int u0012;
    int u0013;
    int u0014;
    int u0015;
    int u0016;
    int u0017;
    int u0018;
    int u0019;
    int u0020;
    int u0021;
    int u0022;
    int u0023;
    int u0024;
    int u0025;
    int u0026;
    int u0027;
    int u0028;
    int u0029;
    int u0030;
    int u0031;
    int u0032;
    int u0033;
    int u0034;
    int u0035;
    int u0036;
    int u0037;
    int u0038;
    int u0039;
    int u0040;
    int u0041;
    int u0042;
    int u0043;
    int u0044;
    int u0045;
    int u0046;
    int u0047;
    int u0048;
    int u0049;
    int u0050;
    int u0051;
    int u0052;
    int u0053;
    int u0054;
    int u0055;
    int u0056;
    int u0057;
    int u0058;
    int u0059;
    int u0060;
    int u0061;
    int u0062;
    int u0063;
    int u0064;
    int u0065;
    int u0066;
    int u0067;
    int u0068;
    int u0069;
    int u0070;
    int u0071;
    int u0072;
    int u0073;
    int u0074;
    int u0075;
    int u0076;
    int u0077;
    int u0078;
    int u0079;
    int u0080;
    int u0081;
    int u0082;
    int u0083;
    int u0084;
    int u0085;
    int u0086;
    int u0087;
    int u0088;
    int u0089;
    int u0090;
    int u0091;
    int u0092;
    int u0093;
    int u0094;
    int u0095;
    int u0096;
    int u0097;
    int u0098;
    int u0099;
    int u0100;
    int u0101;
    int u0102;
    int u0103;
    int u0104;
    int u0105;
    int u0106;
    int u0107;
    int u0108;
    int u0109;
    int u0110;
    int u0111;
    int u0112;
    int u0113;
    int u0114;
    int u0115;
    int u0116;
    int u0117;
    int u0118;
    int u0119;
    int u0120;
    int u0121;
    int u0122;
    int u0123;
    int u0124;
    int u0125;
    int u0126;
    int u0127;
    int u0128;
    int u0129;
    int u0130;
    int u0131;
    int u0132;
    int u0133;
    int u0134;
    int u0135;
    int u0136;
    int u0137;
    int u0138;
    int u0139;
    int u0140;
    int u0141;
    int u0142;
    int u0143;
    int u0144;
    int u0145;
    int u0146;
    int u0147;
    int u0148;
    int u0149;
    int u0150;
    int u0151;
    int u0152;
    int u0153;
    int u0154;
    int u0155;
    int u0156;
    int u0157;
    int u0158;
    int u0159;
    int u0160;
    int u0161;
    int u0162;
    int u0163;
    int u0164;
    int u0165;
    int u0166;
    int u0167;
    int u0168;
    int u0169;
    int u0170;
    int u0171;
    int u0172;
    int u0173;
    int u0174;
    int u0175;
    int u0176;
    int u0177;
    int u0178;
    int u0179;
    int u0180;
    int u0181;
    int u0182;
    int u0183;
    int u0184;
    int u0185;
    int u0186;
    int u0187;
    int u0188;
    int u0189;
    int u0190;
    int u0191;
    int u0192;
    int u0193;
    int u0194;
    int u0195;
    int u0196;
    int u0197;
    int u0198;
    int u0199;
    int u0200;
    int u0201;
    int u0202;
    int u0203;
    int u0204;
    int u0205;
    int u0206;
    int u0207;
    int u0208;
    int u0209;
    int u0210;
    int u0211;
    int u0212;
    int u0213;
    int u0214;
    int u0215;
    int u0216;
    int u0217;
    int u0218;
    int u0219;
    int u0220;
    int u0221;
    int u0222;
    int u0223;
    int u0224;
    int u0225;
    int u0226;
    int u0227;
    int u0228;
    int u0229;
    int u0230;
    int u0231;
    int u0232;
    int u0233;
    int u0234;
    int u0235;
    int u0236;
    int u0237;
    int u0238;
    int u0239;
    int u0240;
    int u0241;
    int u0242;
    int u0243;
    int u0244;
    int u0245;
    int u0246;
    int u0247;
    int u0248;
    int u0249;
    int u0250;
    int u0251;
    int u0252;
    int u0253;
    int u0254;
    int u0255;
    int u0256;
    int u0257;
    int u0258;
    int u0259;
    int u0260;
    int u0261;
    int u0262;
    int u0263;
    int u0264;
    int u0265;
    int u0266;
    int u0267;
    int u0268;
    int u0269;
    int u0270;
    int u0271;
    int u0272;
    int u0273;
    int u0274;
    int u0275;
    int u0276;
    int u0277;
    int u0278;
    int u0279;
    int u0280;
    int u0281;
    int u0282;
    int u0283;
    int u0284;
    int u0285;
    int u0286;
    int u0287;
    int u0288;
    int u0289;
    int u0290;
    int u0291;
    int u0292;
    int u0293;
    int u0294;
    int u0295;
    int u0296;
    int u0297;
    int u0298;
    int u0299;
    int u0300;
    int u0301;
    int u0302;
    int u0303;
    int u0304;
    int u0305;
    int u0306;
    int u0307;
    int u0308;
    int u0309;
    int u0310;
    int u0311;
    int u0312;
    int u0313;
    int u0314;
    int u0315;
    int u0316;
    int u0317;
    int u0318;
    int u0319;
    int u0320;
    int u0321;
    int u0322;
    int u0323;
    int u0324;
    int u0325;
    int u0326;
    int u0327;
    int u0328;
    int u0329;
    int u0330;
    int u0331;
    int u0332;
    int u0333;
    int u0334;
    int u0335;
    int u0336;
    int u0337;
    int u0338;
    int u0339;
    int u0340;
    int u0341;
    int u0342;
    int u0343;
    int u0344;
    int u0345;
    int u0346;
    int u0347;
    int u0348;
    int u0349;
    int u0350;
    int u0351;
    int u0352;
    int u0353;
    int u0354;
    int u0355;
    int u0356;
    int u0357;
    int u0358;
    int u0359;
    int u0360;
    int u0361;
    int u0362;
    int u0363;
    int u0364;
    int u0365;
    int u0366;
    int u0367;
    int u0368;
    int u0369;
    int u0370;
    int u0371;
    int u0372;
    int u0373;
    int u0374;
    int u0375;
    int u0376;
    int u0377;
    int u0378;
    int u0379;
    int u0380;
    int u0381;
    int u0382;
    int u0383;
    int u0384;
    int u0385;
    int u0386;
    int u0387;
    int u0388;
    int u0389;
    int u0390;
    int u0391;
    int u0392;
    int u0393;
    int u0394;
    int u0395;
    int u0396;
    int u0397;
    int u0398;
    int u0399;
    int u0400;
    int u0401;
    int u0402;
    int u0403;
    int u0404;
    int u0405;
    int u0406;
    int u0407;
    int u0408;
    int u0409;
    int u0410;
    int u0411;
    int u0412;
    int u0413;
    int u0414;
    int u0415;
    int u0416;
    int u0417;
    int u0418;
    int u0419;
    int u0420;
    int u0421;
    int u0422;
    int u0423;
    int u0424;
    int u0425;
    int u0426;
    int u0427;
    int u0428;
    int u0429;
    int u0430;
    int u0431;
    int u0432;
    int u0433;
    int u0434;
    int u0435;
    int u0436;
    int u0437;
    int u0438;
    int u0439;
    int u0440;
    int u0441;
    int u0442;
    int u0443;
    int u0444;
    int u0445;
    int u0446;
    int u0447;
    int u0448;
    int u0449;
    int u0450;
    int u0451;
    int u0452;
    int u0453;
    int u0454;
    int u0455;
    int u0456;
    int u0457;
    int u0458;
    int u0459;
    int u0460;
    int u0461;
    int u0462;
    int u0463;
    int u0464;
    int u0465;
    int u0466;
    int u0467;
    int u0468;
    int u0469;
    int u0470;
    int u0471;
    int u0472;
    int u0473;
    int u0474;
    int u0475;
    int u0476;
    int u0477;
    int u0478;
    int u0479;
    int u0480;
    int u0481;
    int u0482;
    int u0483;
    int u0484;
    int u0485;
    int u0486;
    int u0487;
    int u0488;
    int u0489;
    int u0490;
    int u0491;
    int u0492;
    int u0493;
    int u0494;
    int u0495;
    int u0496;
    int u0497;
    int u0498;
    int u0499;
    int u0500;
    int u0501;
    int u0502;
    int u0503;
    int u0504;
    int u0505;
    int u0506;
    int u0507;
    int u0508;
    int u0509;
    int u0510;
    int u0511;
    int u0512;
    int u0513;
    int u0514;
    int u0515;
    int u0516;
    int u0517;
    int u0518;
    int u0519;
    int u0520;
    int u0521;
    int u0522;
    int u0523;
    int u0524;
    int u0525;
    int u0526;
    int u0527;
    int u0528;
    int u0529;
    int u0530;
    int u0531;
    int u0532;
    int u0533;
    int u0534;
    int u0535;
    int u0536;
    int u0537;
    int u0538;
    int u0539;
    int u0540;
    int u0541;
    int u0542;
    int u0543;
    int u0544;
    int u0545;
    int u0546;
    int u0547;
    int u0548;
    int u0549;
    int u0550;
    int u0551;
    int u0552;
    int u0553;
    int u0554;
    int u0555;
    int u0556;
    int u0557;
    int u0558;
    int u0559;
    int u0560;
    int u0561;
    int u0562;
    int u0563;
    int u0564;
    int u0565;
    int u0566;
    int u0567;
    int u0568;
    int u0569;
    int u0570;
    int u0571;
    int u0572;
    int u0573;
    int u0574;
    int u0575;
    int u0576;
    int u0577;
    int u0578;
    int u0579;
    int u0580;
    int u0581;
    int u0582;
    int u0583;
    int u0584;
    int u0585;
    int u0586;
    int u0587;
    int u0588;
    int u0589;
    int u0590;
    int u0591;
    int u0592;
    int u0593;
    int u0594;
    int u0595;
    int u0596;
    int u0597;
    int u0598;
    int u0599;
    int u0600;
    int u0601;
    int u0602;
    int u0603;
    int u0604;
    int u0605;
    int u0606;
    int u0607;
    int u0608;
    int u0609;
    int u0610;
    int u0611;
    int u0612;
    int u0613;
    int u0614;
    int u0615;
    int u0616;
    int u0617;
    int u0618;
    int u0619;
    int u0620;
    int u0621;
    int u0622;
    int u0623;
    int u0624;
    int u0625;
    int u0626;
    int u0627;
    int u0628;
    int u0629;
    int u0630;
    int u0631;
    int u0632;
    int u0633;
    int u0634;
    int u0635;
    int u0636;
    int u0637;
    int u0638;
    int u0639;
    int u0640;
    int u0641;
    int u0642;
    int u0643;
    int u0644;
    int u0645;
    int u0646;
    int u0647;
    int u0648;
    int u0649;
    int u0650;
    int u0651;
    int u0652;
    int u0653;
    int u0654;
    int u0655;
    int u0656;
    int u0657;
    int u0658;
    int u0659;
    int u0660;
    int u0661;
    int u0662;
    int u0663;
    int u0664;
    int u0665;
    int u0666;
    int u0667;
    int u0668;
    int u0669;
    int u0670;
    int u0671;
    int u0672;
    int u0673;
    int u0674;
    int u0675;
    int u0676;
    int u0677;
    int u0678;
    int u0679;
    int u0680;
    int u0681;
    int u0682;
    int u0683;
    int u0684;
    int u0685;
    int u0686;
    int u0687;
    int u0688;
    int u0689;
    int u0690;
    int u0691;
    int u0692;
    int u0693;
    int u0694;
    int u0695;
    int u0696;
    int u0697;
    int u0698;
    int u0699;
    int u0700;
    int u0701;
    int u0702;
    int u0703;
    int u0704;
    int u0705;
    int u0706;
    int u0707;
    int u0708;
    int u0709;
    int u0710;
    int u0711;
    int u0712;
    int u0713;
    int u0714;
    int u0715;
    int u0716;
    int u0717;
    int u0718;
    int u0719;
    int u0720;
    int u0721;
    int u0722;
    int u0723;
    int u0724;
    int u0725;
    int u0726;
    int u0727;
    int u0728;
    int u0729;
    int u0730;
    int u0731;
    int u0732;
    int u0733;
    int u0734;
    int u0735;
    int u0736;
    int u0737;
    int u0738;
    int u0739;
    int u0740;
    int u0741;
    int u0742;
    int u0743;
    int u0744;
    int u0745;
    int u0746;
    int u0747;
    int u0748;
    int u0749;
    int u0750;
    int u0751;
    int u0752;
    int u0753;
    int u0754;
    int u0755;
    int u0756;
    int u0757;
    int u0758;
    int u0759;
    int u0760;
    int u0761;
    int u0762;
    int u0763;
    int u0764;
    int u0765;
    int u0766;
    int u0767;
    int u0768;
    int u0769;
    int u0770;
    int u0771;
    int u0772;
    int u0773;
    int u0774;
    int u0775;
    int u0776;
    int u0777;
    int u0778;
    int u0779;
    int u0780;
    int u0781;
    int u0782;
    int u0783;
    int u0784;
    int u0785;
    int u0786;
    int u0787;
    int u0788;
    int u0789;
    int u0790;
    int u0791;
    int u0792;
    int u0793;
    int u0794;
    int u0795;
    int u0796;
    int u0797;
    int u0798;
    int u0799;
    int u0800;
    int u0801;
    int u0802;
    int u0803;
    int u0804;
    int u0805;
    int u0806;
    int u0807;
    int u0808;
    int u0809;
    int u0810;
    int u0811;
    int u0812;
    int u0813;
    int u0814;
    int u0815;
    int u0816;
    int u0817;
    int u0818;
    int u0819;
    int u0820;
    int u0821;
    int u0822;
    int u0823;
    int u0824;
    int u0825;
    int u0826;
    int u0827;
    int u0828;
    int u0829;
    int u0830;
    int u0831;
    int u0832;
    int u0833;
    int u0834;
    int u0835;
    int u0836;
    int u0837;
    int u0838;
    int u0839;
    int u0840;
    int u0841;
    int u0842;
    int u0843;
    int u0844;
    int u0845;
    int u0846;
    int u0847;
    int u0848;
    int u0849;
    int u0850;
    int u0851;
    int u0852;
    int u0853;
    int u0854;
    int u0855;
    int u0856;
    int u0857;
    int u0858;
    int u0859;
    int u0860;
    int u0861;
    int u0862;
    int u0863;
    int u0864;
    int u0865;
    int u0866;
    int u0867;
    int u0868;
    int u0869;
    int u0870;
    int u0871;
    int u0872;
    int u0873;
    int u0874;
    int u0875;
    int u0876;
    int u0877;
    int u0878;
    int u0879;
    int u0880;
    int u0881;
    int u0882;
    int u0883;
    int u0884;
    int u0885;
    int u0886;
    int u0887;
    int u0888;
    int u0889;
    int u0890;
    int u0891;
    int u0892;
    int u0893;
    int u0894;
    int u0895;
    int u0896;
    int u0897;
    int u0898;
    int u0899;
    int u0900;
    int u0901;
    int u0902;
    int u0903;
    int u0904;
    int u0905;
    int u0906;
    int u0907;
    int u0908;
    int u0909;
    int u0910;
    int u0911;
    int u0912;
    int u0913;
    int u0914;
    int u0915;
    int u0916;
    int u0917;
    int u0918;
    int u0919;
    int u0920;
    int u0921;
    int u0922;
    int u0923;
    int u0924;
    int u0925;
    int u0926;
    int u0927;
    int u0928;
    int u0929;
    int u0930;
    int u0931;
    int u0932;
    int u0933;
    int u0934;
    int u0935;
    int u0936;
    int u0937;
    int u0938;
    int u0939;
    int u0940;
    int u0941;
    int u0942;
    int u0943;
    int u0944;
    int u0945;
    int u0946;
    int u0947;
    int u0948;
    int u0949;
    int u0950;
    int u0951;
    int u0952;
    int u0953;
    int u0954;
    int u0955;
    int u0956;
    int u0957;
    int u0958;
    int u0959;
    int u0960;
    int u0961;
    int u0962;
    int u0963;
    int u0964;
    int u0965;
    int u0966;
    int u0967;
    int u0968;
    int u0969;
    int u0970;
    int u0971;
    int u0972;
    int u0973;
    int u0974;
    int u0975;
    int u0976;
    int u0977;
    int u0978;
    int u0979;
    int u0980;
    int u0981;
    int u0982;
    int u0983;
    int u0984;
    int u0985;
    int u0986;
    int u0987;
    int u0988;
    int u0989;
    int u0990;
    int u0991;
    int u0992;
    int u0993;
    int u0994;
    int u0995;
    int u0996;
    int u0997;
    int u0998;
    int u0999;
    int u1000;
    int u1001;
    int u1002;
    int u1003;
    int u1004;
    int u1005;
    int u1006;
    int u1007;
    int u1008;
    int u1009;
    int u1010;
    int u1011;
    int u1012;
    int u1013;
    int u1014;
    int u1015;
    int u1016;
    int u1017;
    int u1018;
    int u1019;
    int u1020;
    int u1021;
    int u1022;
};

/* 1023 enumeration constants in one enumeration (with a trailing comma,
 * which C99 permits). */
enum c99_wide_enum {
    C99_ENUM_0000,
    C99_ENUM_0001,
    C99_ENUM_0002,
    C99_ENUM_0003,
    C99_ENUM_0004,
    C99_ENUM_0005,
    C99_ENUM_0006,
    C99_ENUM_0007,
    C99_ENUM_0008,
    C99_ENUM_0009,
    C99_ENUM_0010,
    C99_ENUM_0011,
    C99_ENUM_0012,
    C99_ENUM_0013,
    C99_ENUM_0014,
    C99_ENUM_0015,
    C99_ENUM_0016,
    C99_ENUM_0017,
    C99_ENUM_0018,
    C99_ENUM_0019,
    C99_ENUM_0020,
    C99_ENUM_0021,
    C99_ENUM_0022,
    C99_ENUM_0023,
    C99_ENUM_0024,
    C99_ENUM_0025,
    C99_ENUM_0026,
    C99_ENUM_0027,
    C99_ENUM_0028,
    C99_ENUM_0029,
    C99_ENUM_0030,
    C99_ENUM_0031,
    C99_ENUM_0032,
    C99_ENUM_0033,
    C99_ENUM_0034,
    C99_ENUM_0035,
    C99_ENUM_0036,
    C99_ENUM_0037,
    C99_ENUM_0038,
    C99_ENUM_0039,
    C99_ENUM_0040,
    C99_ENUM_0041,
    C99_ENUM_0042,
    C99_ENUM_0043,
    C99_ENUM_0044,
    C99_ENUM_0045,
    C99_ENUM_0046,
    C99_ENUM_0047,
    C99_ENUM_0048,
    C99_ENUM_0049,
    C99_ENUM_0050,
    C99_ENUM_0051,
    C99_ENUM_0052,
    C99_ENUM_0053,
    C99_ENUM_0054,
    C99_ENUM_0055,
    C99_ENUM_0056,
    C99_ENUM_0057,
    C99_ENUM_0058,
    C99_ENUM_0059,
    C99_ENUM_0060,
    C99_ENUM_0061,
    C99_ENUM_0062,
    C99_ENUM_0063,
    C99_ENUM_0064,
    C99_ENUM_0065,
    C99_ENUM_0066,
    C99_ENUM_0067,
    C99_ENUM_0068,
    C99_ENUM_0069,
    C99_ENUM_0070,
    C99_ENUM_0071,
    C99_ENUM_0072,
    C99_ENUM_0073,
    C99_ENUM_0074,
    C99_ENUM_0075,
    C99_ENUM_0076,
    C99_ENUM_0077,
    C99_ENUM_0078,
    C99_ENUM_0079,
    C99_ENUM_0080,
    C99_ENUM_0081,
    C99_ENUM_0082,
    C99_ENUM_0083,
    C99_ENUM_0084,
    C99_ENUM_0085,
    C99_ENUM_0086,
    C99_ENUM_0087,
    C99_ENUM_0088,
    C99_ENUM_0089,
    C99_ENUM_0090,
    C99_ENUM_0091,
    C99_ENUM_0092,
    C99_ENUM_0093,
    C99_ENUM_0094,
    C99_ENUM_0095,
    C99_ENUM_0096,
    C99_ENUM_0097,
    C99_ENUM_0098,
    C99_ENUM_0099,
    C99_ENUM_0100,
    C99_ENUM_0101,
    C99_ENUM_0102,
    C99_ENUM_0103,
    C99_ENUM_0104,
    C99_ENUM_0105,
    C99_ENUM_0106,
    C99_ENUM_0107,
    C99_ENUM_0108,
    C99_ENUM_0109,
    C99_ENUM_0110,
    C99_ENUM_0111,
    C99_ENUM_0112,
    C99_ENUM_0113,
    C99_ENUM_0114,
    C99_ENUM_0115,
    C99_ENUM_0116,
    C99_ENUM_0117,
    C99_ENUM_0118,
    C99_ENUM_0119,
    C99_ENUM_0120,
    C99_ENUM_0121,
    C99_ENUM_0122,
    C99_ENUM_0123,
    C99_ENUM_0124,
    C99_ENUM_0125,
    C99_ENUM_0126,
    C99_ENUM_0127,
    C99_ENUM_0128,
    C99_ENUM_0129,
    C99_ENUM_0130,
    C99_ENUM_0131,
    C99_ENUM_0132,
    C99_ENUM_0133,
    C99_ENUM_0134,
    C99_ENUM_0135,
    C99_ENUM_0136,
    C99_ENUM_0137,
    C99_ENUM_0138,
    C99_ENUM_0139,
    C99_ENUM_0140,
    C99_ENUM_0141,
    C99_ENUM_0142,
    C99_ENUM_0143,
    C99_ENUM_0144,
    C99_ENUM_0145,
    C99_ENUM_0146,
    C99_ENUM_0147,
    C99_ENUM_0148,
    C99_ENUM_0149,
    C99_ENUM_0150,
    C99_ENUM_0151,
    C99_ENUM_0152,
    C99_ENUM_0153,
    C99_ENUM_0154,
    C99_ENUM_0155,
    C99_ENUM_0156,
    C99_ENUM_0157,
    C99_ENUM_0158,
    C99_ENUM_0159,
    C99_ENUM_0160,
    C99_ENUM_0161,
    C99_ENUM_0162,
    C99_ENUM_0163,
    C99_ENUM_0164,
    C99_ENUM_0165,
    C99_ENUM_0166,
    C99_ENUM_0167,
    C99_ENUM_0168,
    C99_ENUM_0169,
    C99_ENUM_0170,
    C99_ENUM_0171,
    C99_ENUM_0172,
    C99_ENUM_0173,
    C99_ENUM_0174,
    C99_ENUM_0175,
    C99_ENUM_0176,
    C99_ENUM_0177,
    C99_ENUM_0178,
    C99_ENUM_0179,
    C99_ENUM_0180,
    C99_ENUM_0181,
    C99_ENUM_0182,
    C99_ENUM_0183,
    C99_ENUM_0184,
    C99_ENUM_0185,
    C99_ENUM_0186,
    C99_ENUM_0187,
    C99_ENUM_0188,
    C99_ENUM_0189,
    C99_ENUM_0190,
    C99_ENUM_0191,
    C99_ENUM_0192,
    C99_ENUM_0193,
    C99_ENUM_0194,
    C99_ENUM_0195,
    C99_ENUM_0196,
    C99_ENUM_0197,
    C99_ENUM_0198,
    C99_ENUM_0199,
    C99_ENUM_0200,
    C99_ENUM_0201,
    C99_ENUM_0202,
    C99_ENUM_0203,
    C99_ENUM_0204,
    C99_ENUM_0205,
    C99_ENUM_0206,
    C99_ENUM_0207,
    C99_ENUM_0208,
    C99_ENUM_0209,
    C99_ENUM_0210,
    C99_ENUM_0211,
    C99_ENUM_0212,
    C99_ENUM_0213,
    C99_ENUM_0214,
    C99_ENUM_0215,
    C99_ENUM_0216,
    C99_ENUM_0217,
    C99_ENUM_0218,
    C99_ENUM_0219,
    C99_ENUM_0220,
    C99_ENUM_0221,
    C99_ENUM_0222,
    C99_ENUM_0223,
    C99_ENUM_0224,
    C99_ENUM_0225,
    C99_ENUM_0226,
    C99_ENUM_0227,
    C99_ENUM_0228,
    C99_ENUM_0229,
    C99_ENUM_0230,
    C99_ENUM_0231,
    C99_ENUM_0232,
    C99_ENUM_0233,
    C99_ENUM_0234,
    C99_ENUM_0235,
    C99_ENUM_0236,
    C99_ENUM_0237,
    C99_ENUM_0238,
    C99_ENUM_0239,
    C99_ENUM_0240,
    C99_ENUM_0241,
    C99_ENUM_0242,
    C99_ENUM_0243,
    C99_ENUM_0244,
    C99_ENUM_0245,
    C99_ENUM_0246,
    C99_ENUM_0247,
    C99_ENUM_0248,
    C99_ENUM_0249,
    C99_ENUM_0250,
    C99_ENUM_0251,
    C99_ENUM_0252,
    C99_ENUM_0253,
    C99_ENUM_0254,
    C99_ENUM_0255,
    C99_ENUM_0256,
    C99_ENUM_0257,
    C99_ENUM_0258,
    C99_ENUM_0259,
    C99_ENUM_0260,
    C99_ENUM_0261,
    C99_ENUM_0262,
    C99_ENUM_0263,
    C99_ENUM_0264,
    C99_ENUM_0265,
    C99_ENUM_0266,
    C99_ENUM_0267,
    C99_ENUM_0268,
    C99_ENUM_0269,
    C99_ENUM_0270,
    C99_ENUM_0271,
    C99_ENUM_0272,
    C99_ENUM_0273,
    C99_ENUM_0274,
    C99_ENUM_0275,
    C99_ENUM_0276,
    C99_ENUM_0277,
    C99_ENUM_0278,
    C99_ENUM_0279,
    C99_ENUM_0280,
    C99_ENUM_0281,
    C99_ENUM_0282,
    C99_ENUM_0283,
    C99_ENUM_0284,
    C99_ENUM_0285,
    C99_ENUM_0286,
    C99_ENUM_0287,
    C99_ENUM_0288,
    C99_ENUM_0289,
    C99_ENUM_0290,
    C99_ENUM_0291,
    C99_ENUM_0292,
    C99_ENUM_0293,
    C99_ENUM_0294,
    C99_ENUM_0295,
    C99_ENUM_0296,
    C99_ENUM_0297,
    C99_ENUM_0298,
    C99_ENUM_0299,
    C99_ENUM_0300,
    C99_ENUM_0301,
    C99_ENUM_0302,
    C99_ENUM_0303,
    C99_ENUM_0304,
    C99_ENUM_0305,
    C99_ENUM_0306,
    C99_ENUM_0307,
    C99_ENUM_0308,
    C99_ENUM_0309,
    C99_ENUM_0310,
    C99_ENUM_0311,
    C99_ENUM_0312,
    C99_ENUM_0313,
    C99_ENUM_0314,
    C99_ENUM_0315,
    C99_ENUM_0316,
    C99_ENUM_0317,
    C99_ENUM_0318,
    C99_ENUM_0319,
    C99_ENUM_0320,
    C99_ENUM_0321,
    C99_ENUM_0322,
    C99_ENUM_0323,
    C99_ENUM_0324,
    C99_ENUM_0325,
    C99_ENUM_0326,
    C99_ENUM_0327,
    C99_ENUM_0328,
    C99_ENUM_0329,
    C99_ENUM_0330,
    C99_ENUM_0331,
    C99_ENUM_0332,
    C99_ENUM_0333,
    C99_ENUM_0334,
    C99_ENUM_0335,
    C99_ENUM_0336,
    C99_ENUM_0337,
    C99_ENUM_0338,
    C99_ENUM_0339,
    C99_ENUM_0340,
    C99_ENUM_0341,
    C99_ENUM_0342,
    C99_ENUM_0343,
    C99_ENUM_0344,
    C99_ENUM_0345,
    C99_ENUM_0346,
    C99_ENUM_0347,
    C99_ENUM_0348,
    C99_ENUM_0349,
    C99_ENUM_0350,
    C99_ENUM_0351,
    C99_ENUM_0352,
    C99_ENUM_0353,
    C99_ENUM_0354,
    C99_ENUM_0355,
    C99_ENUM_0356,
    C99_ENUM_0357,
    C99_ENUM_0358,
    C99_ENUM_0359,
    C99_ENUM_0360,
    C99_ENUM_0361,
    C99_ENUM_0362,
    C99_ENUM_0363,
    C99_ENUM_0364,
    C99_ENUM_0365,
    C99_ENUM_0366,
    C99_ENUM_0367,
    C99_ENUM_0368,
    C99_ENUM_0369,
    C99_ENUM_0370,
    C99_ENUM_0371,
    C99_ENUM_0372,
    C99_ENUM_0373,
    C99_ENUM_0374,
    C99_ENUM_0375,
    C99_ENUM_0376,
    C99_ENUM_0377,
    C99_ENUM_0378,
    C99_ENUM_0379,
    C99_ENUM_0380,
    C99_ENUM_0381,
    C99_ENUM_0382,
    C99_ENUM_0383,
    C99_ENUM_0384,
    C99_ENUM_0385,
    C99_ENUM_0386,
    C99_ENUM_0387,
    C99_ENUM_0388,
    C99_ENUM_0389,
    C99_ENUM_0390,
    C99_ENUM_0391,
    C99_ENUM_0392,
    C99_ENUM_0393,
    C99_ENUM_0394,
    C99_ENUM_0395,
    C99_ENUM_0396,
    C99_ENUM_0397,
    C99_ENUM_0398,
    C99_ENUM_0399,
    C99_ENUM_0400,
    C99_ENUM_0401,
    C99_ENUM_0402,
    C99_ENUM_0403,
    C99_ENUM_0404,
    C99_ENUM_0405,
    C99_ENUM_0406,
    C99_ENUM_0407,
    C99_ENUM_0408,
    C99_ENUM_0409,
    C99_ENUM_0410,
    C99_ENUM_0411,
    C99_ENUM_0412,
    C99_ENUM_0413,
    C99_ENUM_0414,
    C99_ENUM_0415,
    C99_ENUM_0416,
    C99_ENUM_0417,
    C99_ENUM_0418,
    C99_ENUM_0419,
    C99_ENUM_0420,
    C99_ENUM_0421,
    C99_ENUM_0422,
    C99_ENUM_0423,
    C99_ENUM_0424,
    C99_ENUM_0425,
    C99_ENUM_0426,
    C99_ENUM_0427,
    C99_ENUM_0428,
    C99_ENUM_0429,
    C99_ENUM_0430,
    C99_ENUM_0431,
    C99_ENUM_0432,
    C99_ENUM_0433,
    C99_ENUM_0434,
    C99_ENUM_0435,
    C99_ENUM_0436,
    C99_ENUM_0437,
    C99_ENUM_0438,
    C99_ENUM_0439,
    C99_ENUM_0440,
    C99_ENUM_0441,
    C99_ENUM_0442,
    C99_ENUM_0443,
    C99_ENUM_0444,
    C99_ENUM_0445,
    C99_ENUM_0446,
    C99_ENUM_0447,
    C99_ENUM_0448,
    C99_ENUM_0449,
    C99_ENUM_0450,
    C99_ENUM_0451,
    C99_ENUM_0452,
    C99_ENUM_0453,
    C99_ENUM_0454,
    C99_ENUM_0455,
    C99_ENUM_0456,
    C99_ENUM_0457,
    C99_ENUM_0458,
    C99_ENUM_0459,
    C99_ENUM_0460,
    C99_ENUM_0461,
    C99_ENUM_0462,
    C99_ENUM_0463,
    C99_ENUM_0464,
    C99_ENUM_0465,
    C99_ENUM_0466,
    C99_ENUM_0467,
    C99_ENUM_0468,
    C99_ENUM_0469,
    C99_ENUM_0470,
    C99_ENUM_0471,
    C99_ENUM_0472,
    C99_ENUM_0473,
    C99_ENUM_0474,
    C99_ENUM_0475,
    C99_ENUM_0476,
    C99_ENUM_0477,
    C99_ENUM_0478,
    C99_ENUM_0479,
    C99_ENUM_0480,
    C99_ENUM_0481,
    C99_ENUM_0482,
    C99_ENUM_0483,
    C99_ENUM_0484,
    C99_ENUM_0485,
    C99_ENUM_0486,
    C99_ENUM_0487,
    C99_ENUM_0488,
    C99_ENUM_0489,
    C99_ENUM_0490,
    C99_ENUM_0491,
    C99_ENUM_0492,
    C99_ENUM_0493,
    C99_ENUM_0494,
    C99_ENUM_0495,
    C99_ENUM_0496,
    C99_ENUM_0497,
    C99_ENUM_0498,
    C99_ENUM_0499,
    C99_ENUM_0500,
    C99_ENUM_0501,
    C99_ENUM_0502,
    C99_ENUM_0503,
    C99_ENUM_0504,
    C99_ENUM_0505,
    C99_ENUM_0506,
    C99_ENUM_0507,
    C99_ENUM_0508,
    C99_ENUM_0509,
    C99_ENUM_0510,
    C99_ENUM_0511,
    C99_ENUM_0512,
    C99_ENUM_0513,
    C99_ENUM_0514,
    C99_ENUM_0515,
    C99_ENUM_0516,
    C99_ENUM_0517,
    C99_ENUM_0518,
    C99_ENUM_0519,
    C99_ENUM_0520,
    C99_ENUM_0521,
    C99_ENUM_0522,
    C99_ENUM_0523,
    C99_ENUM_0524,
    C99_ENUM_0525,
    C99_ENUM_0526,
    C99_ENUM_0527,
    C99_ENUM_0528,
    C99_ENUM_0529,
    C99_ENUM_0530,
    C99_ENUM_0531,
    C99_ENUM_0532,
    C99_ENUM_0533,
    C99_ENUM_0534,
    C99_ENUM_0535,
    C99_ENUM_0536,
    C99_ENUM_0537,
    C99_ENUM_0538,
    C99_ENUM_0539,
    C99_ENUM_0540,
    C99_ENUM_0541,
    C99_ENUM_0542,
    C99_ENUM_0543,
    C99_ENUM_0544,
    C99_ENUM_0545,
    C99_ENUM_0546,
    C99_ENUM_0547,
    C99_ENUM_0548,
    C99_ENUM_0549,
    C99_ENUM_0550,
    C99_ENUM_0551,
    C99_ENUM_0552,
    C99_ENUM_0553,
    C99_ENUM_0554,
    C99_ENUM_0555,
    C99_ENUM_0556,
    C99_ENUM_0557,
    C99_ENUM_0558,
    C99_ENUM_0559,
    C99_ENUM_0560,
    C99_ENUM_0561,
    C99_ENUM_0562,
    C99_ENUM_0563,
    C99_ENUM_0564,
    C99_ENUM_0565,
    C99_ENUM_0566,
    C99_ENUM_0567,
    C99_ENUM_0568,
    C99_ENUM_0569,
    C99_ENUM_0570,
    C99_ENUM_0571,
    C99_ENUM_0572,
    C99_ENUM_0573,
    C99_ENUM_0574,
    C99_ENUM_0575,
    C99_ENUM_0576,
    C99_ENUM_0577,
    C99_ENUM_0578,
    C99_ENUM_0579,
    C99_ENUM_0580,
    C99_ENUM_0581,
    C99_ENUM_0582,
    C99_ENUM_0583,
    C99_ENUM_0584,
    C99_ENUM_0585,
    C99_ENUM_0586,
    C99_ENUM_0587,
    C99_ENUM_0588,
    C99_ENUM_0589,
    C99_ENUM_0590,
    C99_ENUM_0591,
    C99_ENUM_0592,
    C99_ENUM_0593,
    C99_ENUM_0594,
    C99_ENUM_0595,
    C99_ENUM_0596,
    C99_ENUM_0597,
    C99_ENUM_0598,
    C99_ENUM_0599,
    C99_ENUM_0600,
    C99_ENUM_0601,
    C99_ENUM_0602,
    C99_ENUM_0603,
    C99_ENUM_0604,
    C99_ENUM_0605,
    C99_ENUM_0606,
    C99_ENUM_0607,
    C99_ENUM_0608,
    C99_ENUM_0609,
    C99_ENUM_0610,
    C99_ENUM_0611,
    C99_ENUM_0612,
    C99_ENUM_0613,
    C99_ENUM_0614,
    C99_ENUM_0615,
    C99_ENUM_0616,
    C99_ENUM_0617,
    C99_ENUM_0618,
    C99_ENUM_0619,
    C99_ENUM_0620,
    C99_ENUM_0621,
    C99_ENUM_0622,
    C99_ENUM_0623,
    C99_ENUM_0624,
    C99_ENUM_0625,
    C99_ENUM_0626,
    C99_ENUM_0627,
    C99_ENUM_0628,
    C99_ENUM_0629,
    C99_ENUM_0630,
    C99_ENUM_0631,
    C99_ENUM_0632,
    C99_ENUM_0633,
    C99_ENUM_0634,
    C99_ENUM_0635,
    C99_ENUM_0636,
    C99_ENUM_0637,
    C99_ENUM_0638,
    C99_ENUM_0639,
    C99_ENUM_0640,
    C99_ENUM_0641,
    C99_ENUM_0642,
    C99_ENUM_0643,
    C99_ENUM_0644,
    C99_ENUM_0645,
    C99_ENUM_0646,
    C99_ENUM_0647,
    C99_ENUM_0648,
    C99_ENUM_0649,
    C99_ENUM_0650,
    C99_ENUM_0651,
    C99_ENUM_0652,
    C99_ENUM_0653,
    C99_ENUM_0654,
    C99_ENUM_0655,
    C99_ENUM_0656,
    C99_ENUM_0657,
    C99_ENUM_0658,
    C99_ENUM_0659,
    C99_ENUM_0660,
    C99_ENUM_0661,
    C99_ENUM_0662,
    C99_ENUM_0663,
    C99_ENUM_0664,
    C99_ENUM_0665,
    C99_ENUM_0666,
    C99_ENUM_0667,
    C99_ENUM_0668,
    C99_ENUM_0669,
    C99_ENUM_0670,
    C99_ENUM_0671,
    C99_ENUM_0672,
    C99_ENUM_0673,
    C99_ENUM_0674,
    C99_ENUM_0675,
    C99_ENUM_0676,
    C99_ENUM_0677,
    C99_ENUM_0678,
    C99_ENUM_0679,
    C99_ENUM_0680,
    C99_ENUM_0681,
    C99_ENUM_0682,
    C99_ENUM_0683,
    C99_ENUM_0684,
    C99_ENUM_0685,
    C99_ENUM_0686,
    C99_ENUM_0687,
    C99_ENUM_0688,
    C99_ENUM_0689,
    C99_ENUM_0690,
    C99_ENUM_0691,
    C99_ENUM_0692,
    C99_ENUM_0693,
    C99_ENUM_0694,
    C99_ENUM_0695,
    C99_ENUM_0696,
    C99_ENUM_0697,
    C99_ENUM_0698,
    C99_ENUM_0699,
    C99_ENUM_0700,
    C99_ENUM_0701,
    C99_ENUM_0702,
    C99_ENUM_0703,
    C99_ENUM_0704,
    C99_ENUM_0705,
    C99_ENUM_0706,
    C99_ENUM_0707,
    C99_ENUM_0708,
    C99_ENUM_0709,
    C99_ENUM_0710,
    C99_ENUM_0711,
    C99_ENUM_0712,
    C99_ENUM_0713,
    C99_ENUM_0714,
    C99_ENUM_0715,
    C99_ENUM_0716,
    C99_ENUM_0717,
    C99_ENUM_0718,
    C99_ENUM_0719,
    C99_ENUM_0720,
    C99_ENUM_0721,
    C99_ENUM_0722,
    C99_ENUM_0723,
    C99_ENUM_0724,
    C99_ENUM_0725,
    C99_ENUM_0726,
    C99_ENUM_0727,
    C99_ENUM_0728,
    C99_ENUM_0729,
    C99_ENUM_0730,
    C99_ENUM_0731,
    C99_ENUM_0732,
    C99_ENUM_0733,
    C99_ENUM_0734,
    C99_ENUM_0735,
    C99_ENUM_0736,
    C99_ENUM_0737,
    C99_ENUM_0738,
    C99_ENUM_0739,
    C99_ENUM_0740,
    C99_ENUM_0741,
    C99_ENUM_0742,
    C99_ENUM_0743,
    C99_ENUM_0744,
    C99_ENUM_0745,
    C99_ENUM_0746,
    C99_ENUM_0747,
    C99_ENUM_0748,
    C99_ENUM_0749,
    C99_ENUM_0750,
    C99_ENUM_0751,
    C99_ENUM_0752,
    C99_ENUM_0753,
    C99_ENUM_0754,
    C99_ENUM_0755,
    C99_ENUM_0756,
    C99_ENUM_0757,
    C99_ENUM_0758,
    C99_ENUM_0759,
    C99_ENUM_0760,
    C99_ENUM_0761,
    C99_ENUM_0762,
    C99_ENUM_0763,
    C99_ENUM_0764,
    C99_ENUM_0765,
    C99_ENUM_0766,
    C99_ENUM_0767,
    C99_ENUM_0768,
    C99_ENUM_0769,
    C99_ENUM_0770,
    C99_ENUM_0771,
    C99_ENUM_0772,
    C99_ENUM_0773,
    C99_ENUM_0774,
    C99_ENUM_0775,
    C99_ENUM_0776,
    C99_ENUM_0777,
    C99_ENUM_0778,
    C99_ENUM_0779,
    C99_ENUM_0780,
    C99_ENUM_0781,
    C99_ENUM_0782,
    C99_ENUM_0783,
    C99_ENUM_0784,
    C99_ENUM_0785,
    C99_ENUM_0786,
    C99_ENUM_0787,
    C99_ENUM_0788,
    C99_ENUM_0789,
    C99_ENUM_0790,
    C99_ENUM_0791,
    C99_ENUM_0792,
    C99_ENUM_0793,
    C99_ENUM_0794,
    C99_ENUM_0795,
    C99_ENUM_0796,
    C99_ENUM_0797,
    C99_ENUM_0798,
    C99_ENUM_0799,
    C99_ENUM_0800,
    C99_ENUM_0801,
    C99_ENUM_0802,
    C99_ENUM_0803,
    C99_ENUM_0804,
    C99_ENUM_0805,
    C99_ENUM_0806,
    C99_ENUM_0807,
    C99_ENUM_0808,
    C99_ENUM_0809,
    C99_ENUM_0810,
    C99_ENUM_0811,
    C99_ENUM_0812,
    C99_ENUM_0813,
    C99_ENUM_0814,
    C99_ENUM_0815,
    C99_ENUM_0816,
    C99_ENUM_0817,
    C99_ENUM_0818,
    C99_ENUM_0819,
    C99_ENUM_0820,
    C99_ENUM_0821,
    C99_ENUM_0822,
    C99_ENUM_0823,
    C99_ENUM_0824,
    C99_ENUM_0825,
    C99_ENUM_0826,
    C99_ENUM_0827,
    C99_ENUM_0828,
    C99_ENUM_0829,
    C99_ENUM_0830,
    C99_ENUM_0831,
    C99_ENUM_0832,
    C99_ENUM_0833,
    C99_ENUM_0834,
    C99_ENUM_0835,
    C99_ENUM_0836,
    C99_ENUM_0837,
    C99_ENUM_0838,
    C99_ENUM_0839,
    C99_ENUM_0840,
    C99_ENUM_0841,
    C99_ENUM_0842,
    C99_ENUM_0843,
    C99_ENUM_0844,
    C99_ENUM_0845,
    C99_ENUM_0846,
    C99_ENUM_0847,
    C99_ENUM_0848,
    C99_ENUM_0849,
    C99_ENUM_0850,
    C99_ENUM_0851,
    C99_ENUM_0852,
    C99_ENUM_0853,
    C99_ENUM_0854,
    C99_ENUM_0855,
    C99_ENUM_0856,
    C99_ENUM_0857,
    C99_ENUM_0858,
    C99_ENUM_0859,
    C99_ENUM_0860,
    C99_ENUM_0861,
    C99_ENUM_0862,
    C99_ENUM_0863,
    C99_ENUM_0864,
    C99_ENUM_0865,
    C99_ENUM_0866,
    C99_ENUM_0867,
    C99_ENUM_0868,
    C99_ENUM_0869,
    C99_ENUM_0870,
    C99_ENUM_0871,
    C99_ENUM_0872,
    C99_ENUM_0873,
    C99_ENUM_0874,
    C99_ENUM_0875,
    C99_ENUM_0876,
    C99_ENUM_0877,
    C99_ENUM_0878,
    C99_ENUM_0879,
    C99_ENUM_0880,
    C99_ENUM_0881,
    C99_ENUM_0882,
    C99_ENUM_0883,
    C99_ENUM_0884,
    C99_ENUM_0885,
    C99_ENUM_0886,
    C99_ENUM_0887,
    C99_ENUM_0888,
    C99_ENUM_0889,
    C99_ENUM_0890,
    C99_ENUM_0891,
    C99_ENUM_0892,
    C99_ENUM_0893,
    C99_ENUM_0894,
    C99_ENUM_0895,
    C99_ENUM_0896,
    C99_ENUM_0897,
    C99_ENUM_0898,
    C99_ENUM_0899,
    C99_ENUM_0900,
    C99_ENUM_0901,
    C99_ENUM_0902,
    C99_ENUM_0903,
    C99_ENUM_0904,
    C99_ENUM_0905,
    C99_ENUM_0906,
    C99_ENUM_0907,
    C99_ENUM_0908,
    C99_ENUM_0909,
    C99_ENUM_0910,
    C99_ENUM_0911,
    C99_ENUM_0912,
    C99_ENUM_0913,
    C99_ENUM_0914,
    C99_ENUM_0915,
    C99_ENUM_0916,
    C99_ENUM_0917,
    C99_ENUM_0918,
    C99_ENUM_0919,
    C99_ENUM_0920,
    C99_ENUM_0921,
    C99_ENUM_0922,
    C99_ENUM_0923,
    C99_ENUM_0924,
    C99_ENUM_0925,
    C99_ENUM_0926,
    C99_ENUM_0927,
    C99_ENUM_0928,
    C99_ENUM_0929,
    C99_ENUM_0930,
    C99_ENUM_0931,
    C99_ENUM_0932,
    C99_ENUM_0933,
    C99_ENUM_0934,
    C99_ENUM_0935,
    C99_ENUM_0936,
    C99_ENUM_0937,
    C99_ENUM_0938,
    C99_ENUM_0939,
    C99_ENUM_0940,
    C99_ENUM_0941,
    C99_ENUM_0942,
    C99_ENUM_0943,
    C99_ENUM_0944,
    C99_ENUM_0945,
    C99_ENUM_0946,
    C99_ENUM_0947,
    C99_ENUM_0948,
    C99_ENUM_0949,
    C99_ENUM_0950,
    C99_ENUM_0951,
    C99_ENUM_0952,
    C99_ENUM_0953,
    C99_ENUM_0954,
    C99_ENUM_0955,
    C99_ENUM_0956,
    C99_ENUM_0957,
    C99_ENUM_0958,
    C99_ENUM_0959,
    C99_ENUM_0960,
    C99_ENUM_0961,
    C99_ENUM_0962,
    C99_ENUM_0963,
    C99_ENUM_0964,
    C99_ENUM_0965,
    C99_ENUM_0966,
    C99_ENUM_0967,
    C99_ENUM_0968,
    C99_ENUM_0969,
    C99_ENUM_0970,
    C99_ENUM_0971,
    C99_ENUM_0972,
    C99_ENUM_0973,
    C99_ENUM_0974,
    C99_ENUM_0975,
    C99_ENUM_0976,
    C99_ENUM_0977,
    C99_ENUM_0978,
    C99_ENUM_0979,
    C99_ENUM_0980,
    C99_ENUM_0981,
    C99_ENUM_0982,
    C99_ENUM_0983,
    C99_ENUM_0984,
    C99_ENUM_0985,
    C99_ENUM_0986,
    C99_ENUM_0987,
    C99_ENUM_0988,
    C99_ENUM_0989,
    C99_ENUM_0990,
    C99_ENUM_0991,
    C99_ENUM_0992,
    C99_ENUM_0993,
    C99_ENUM_0994,
    C99_ENUM_0995,
    C99_ENUM_0996,
    C99_ENUM_0997,
    C99_ENUM_0998,
    C99_ENUM_0999,
    C99_ENUM_1000,
    C99_ENUM_1001,
    C99_ENUM_1002,
    C99_ENUM_1003,
    C99_ENUM_1004,
    C99_ENUM_1005,
    C99_ENUM_1006,
    C99_ENUM_1007,
    C99_ENUM_1008,
    C99_ENUM_1009,
    C99_ENUM_1010,
    C99_ENUM_1011,
    C99_ENUM_1012,
    C99_ENUM_1013,
    C99_ENUM_1014,
    C99_ENUM_1015,
    C99_ENUM_1016,
    C99_ENUM_1017,
    C99_ENUM_1018,
    C99_ENUM_1019,
    C99_ENUM_1020,
    C99_ENUM_1021,
    C99_ENUM_1022,
};

/* 1023 case labels (plus default) in one switch statement. */
static int c99_many_cases(int selector)
{
    int n = 0;
    switch (selector) {
    case 0: n = 0; break;
    case 1: n = 1; break;
    case 2: n = 2; break;
    case 3: n = 3; break;
    case 4: n = 4; break;
    case 5: n = 5; break;
    case 6: n = 6; break;
    case 7: n = 7; break;
    case 8: n = 8; break;
    case 9: n = 9; break;
    case 10: n = 10; break;
    case 11: n = 11; break;
    case 12: n = 12; break;
    case 13: n = 13; break;
    case 14: n = 14; break;
    case 15: n = 15; break;
    case 16: n = 16; break;
    case 17: n = 17; break;
    case 18: n = 18; break;
    case 19: n = 19; break;
    case 20: n = 20; break;
    case 21: n = 21; break;
    case 22: n = 22; break;
    case 23: n = 23; break;
    case 24: n = 24; break;
    case 25: n = 25; break;
    case 26: n = 26; break;
    case 27: n = 27; break;
    case 28: n = 28; break;
    case 29: n = 29; break;
    case 30: n = 30; break;
    case 31: n = 31; break;
    case 32: n = 32; break;
    case 33: n = 33; break;
    case 34: n = 34; break;
    case 35: n = 35; break;
    case 36: n = 36; break;
    case 37: n = 37; break;
    case 38: n = 38; break;
    case 39: n = 39; break;
    case 40: n = 40; break;
    case 41: n = 41; break;
    case 42: n = 42; break;
    case 43: n = 43; break;
    case 44: n = 44; break;
    case 45: n = 45; break;
    case 46: n = 46; break;
    case 47: n = 47; break;
    case 48: n = 48; break;
    case 49: n = 49; break;
    case 50: n = 50; break;
    case 51: n = 51; break;
    case 52: n = 52; break;
    case 53: n = 53; break;
    case 54: n = 54; break;
    case 55: n = 55; break;
    case 56: n = 56; break;
    case 57: n = 57; break;
    case 58: n = 58; break;
    case 59: n = 59; break;
    case 60: n = 60; break;
    case 61: n = 61; break;
    case 62: n = 62; break;
    case 63: n = 63; break;
    case 64: n = 64; break;
    case 65: n = 65; break;
    case 66: n = 66; break;
    case 67: n = 67; break;
    case 68: n = 68; break;
    case 69: n = 69; break;
    case 70: n = 70; break;
    case 71: n = 71; break;
    case 72: n = 72; break;
    case 73: n = 73; break;
    case 74: n = 74; break;
    case 75: n = 75; break;
    case 76: n = 76; break;
    case 77: n = 77; break;
    case 78: n = 78; break;
    case 79: n = 79; break;
    case 80: n = 80; break;
    case 81: n = 81; break;
    case 82: n = 82; break;
    case 83: n = 83; break;
    case 84: n = 84; break;
    case 85: n = 85; break;
    case 86: n = 86; break;
    case 87: n = 87; break;
    case 88: n = 88; break;
    case 89: n = 89; break;
    case 90: n = 90; break;
    case 91: n = 91; break;
    case 92: n = 92; break;
    case 93: n = 93; break;
    case 94: n = 94; break;
    case 95: n = 95; break;
    case 96: n = 96; break;
    case 97: n = 97; break;
    case 98: n = 98; break;
    case 99: n = 99; break;
    case 100: n = 100; break;
    case 101: n = 101; break;
    case 102: n = 102; break;
    case 103: n = 103; break;
    case 104: n = 104; break;
    case 105: n = 105; break;
    case 106: n = 106; break;
    case 107: n = 107; break;
    case 108: n = 108; break;
    case 109: n = 109; break;
    case 110: n = 110; break;
    case 111: n = 111; break;
    case 112: n = 112; break;
    case 113: n = 113; break;
    case 114: n = 114; break;
    case 115: n = 115; break;
    case 116: n = 116; break;
    case 117: n = 117; break;
    case 118: n = 118; break;
    case 119: n = 119; break;
    case 120: n = 120; break;
    case 121: n = 121; break;
    case 122: n = 122; break;
    case 123: n = 123; break;
    case 124: n = 124; break;
    case 125: n = 125; break;
    case 126: n = 126; break;
    case 127: n = 127; break;
    case 128: n = 128; break;
    case 129: n = 129; break;
    case 130: n = 130; break;
    case 131: n = 131; break;
    case 132: n = 132; break;
    case 133: n = 133; break;
    case 134: n = 134; break;
    case 135: n = 135; break;
    case 136: n = 136; break;
    case 137: n = 137; break;
    case 138: n = 138; break;
    case 139: n = 139; break;
    case 140: n = 140; break;
    case 141: n = 141; break;
    case 142: n = 142; break;
    case 143: n = 143; break;
    case 144: n = 144; break;
    case 145: n = 145; break;
    case 146: n = 146; break;
    case 147: n = 147; break;
    case 148: n = 148; break;
    case 149: n = 149; break;
    case 150: n = 150; break;
    case 151: n = 151; break;
    case 152: n = 152; break;
    case 153: n = 153; break;
    case 154: n = 154; break;
    case 155: n = 155; break;
    case 156: n = 156; break;
    case 157: n = 157; break;
    case 158: n = 158; break;
    case 159: n = 159; break;
    case 160: n = 160; break;
    case 161: n = 161; break;
    case 162: n = 162; break;
    case 163: n = 163; break;
    case 164: n = 164; break;
    case 165: n = 165; break;
    case 166: n = 166; break;
    case 167: n = 167; break;
    case 168: n = 168; break;
    case 169: n = 169; break;
    case 170: n = 170; break;
    case 171: n = 171; break;
    case 172: n = 172; break;
    case 173: n = 173; break;
    case 174: n = 174; break;
    case 175: n = 175; break;
    case 176: n = 176; break;
    case 177: n = 177; break;
    case 178: n = 178; break;
    case 179: n = 179; break;
    case 180: n = 180; break;
    case 181: n = 181; break;
    case 182: n = 182; break;
    case 183: n = 183; break;
    case 184: n = 184; break;
    case 185: n = 185; break;
    case 186: n = 186; break;
    case 187: n = 187; break;
    case 188: n = 188; break;
    case 189: n = 189; break;
    case 190: n = 190; break;
    case 191: n = 191; break;
    case 192: n = 192; break;
    case 193: n = 193; break;
    case 194: n = 194; break;
    case 195: n = 195; break;
    case 196: n = 196; break;
    case 197: n = 197; break;
    case 198: n = 198; break;
    case 199: n = 199; break;
    case 200: n = 200; break;
    case 201: n = 201; break;
    case 202: n = 202; break;
    case 203: n = 203; break;
    case 204: n = 204; break;
    case 205: n = 205; break;
    case 206: n = 206; break;
    case 207: n = 207; break;
    case 208: n = 208; break;
    case 209: n = 209; break;
    case 210: n = 210; break;
    case 211: n = 211; break;
    case 212: n = 212; break;
    case 213: n = 213; break;
    case 214: n = 214; break;
    case 215: n = 215; break;
    case 216: n = 216; break;
    case 217: n = 217; break;
    case 218: n = 218; break;
    case 219: n = 219; break;
    case 220: n = 220; break;
    case 221: n = 221; break;
    case 222: n = 222; break;
    case 223: n = 223; break;
    case 224: n = 224; break;
    case 225: n = 225; break;
    case 226: n = 226; break;
    case 227: n = 227; break;
    case 228: n = 228; break;
    case 229: n = 229; break;
    case 230: n = 230; break;
    case 231: n = 231; break;
    case 232: n = 232; break;
    case 233: n = 233; break;
    case 234: n = 234; break;
    case 235: n = 235; break;
    case 236: n = 236; break;
    case 237: n = 237; break;
    case 238: n = 238; break;
    case 239: n = 239; break;
    case 240: n = 240; break;
    case 241: n = 241; break;
    case 242: n = 242; break;
    case 243: n = 243; break;
    case 244: n = 244; break;
    case 245: n = 245; break;
    case 246: n = 246; break;
    case 247: n = 247; break;
    case 248: n = 248; break;
    case 249: n = 249; break;
    case 250: n = 250; break;
    case 251: n = 251; break;
    case 252: n = 252; break;
    case 253: n = 253; break;
    case 254: n = 254; break;
    case 255: n = 255; break;
    case 256: n = 256; break;
    case 257: n = 257; break;
    case 258: n = 258; break;
    case 259: n = 259; break;
    case 260: n = 260; break;
    case 261: n = 261; break;
    case 262: n = 262; break;
    case 263: n = 263; break;
    case 264: n = 264; break;
    case 265: n = 265; break;
    case 266: n = 266; break;
    case 267: n = 267; break;
    case 268: n = 268; break;
    case 269: n = 269; break;
    case 270: n = 270; break;
    case 271: n = 271; break;
    case 272: n = 272; break;
    case 273: n = 273; break;
    case 274: n = 274; break;
    case 275: n = 275; break;
    case 276: n = 276; break;
    case 277: n = 277; break;
    case 278: n = 278; break;
    case 279: n = 279; break;
    case 280: n = 280; break;
    case 281: n = 281; break;
    case 282: n = 282; break;
    case 283: n = 283; break;
    case 284: n = 284; break;
    case 285: n = 285; break;
    case 286: n = 286; break;
    case 287: n = 287; break;
    case 288: n = 288; break;
    case 289: n = 289; break;
    case 290: n = 290; break;
    case 291: n = 291; break;
    case 292: n = 292; break;
    case 293: n = 293; break;
    case 294: n = 294; break;
    case 295: n = 295; break;
    case 296: n = 296; break;
    case 297: n = 297; break;
    case 298: n = 298; break;
    case 299: n = 299; break;
    case 300: n = 300; break;
    case 301: n = 301; break;
    case 302: n = 302; break;
    case 303: n = 303; break;
    case 304: n = 304; break;
    case 305: n = 305; break;
    case 306: n = 306; break;
    case 307: n = 307; break;
    case 308: n = 308; break;
    case 309: n = 309; break;
    case 310: n = 310; break;
    case 311: n = 311; break;
    case 312: n = 312; break;
    case 313: n = 313; break;
    case 314: n = 314; break;
    case 315: n = 315; break;
    case 316: n = 316; break;
    case 317: n = 317; break;
    case 318: n = 318; break;
    case 319: n = 319; break;
    case 320: n = 320; break;
    case 321: n = 321; break;
    case 322: n = 322; break;
    case 323: n = 323; break;
    case 324: n = 324; break;
    case 325: n = 325; break;
    case 326: n = 326; break;
    case 327: n = 327; break;
    case 328: n = 328; break;
    case 329: n = 329; break;
    case 330: n = 330; break;
    case 331: n = 331; break;
    case 332: n = 332; break;
    case 333: n = 333; break;
    case 334: n = 334; break;
    case 335: n = 335; break;
    case 336: n = 336; break;
    case 337: n = 337; break;
    case 338: n = 338; break;
    case 339: n = 339; break;
    case 340: n = 340; break;
    case 341: n = 341; break;
    case 342: n = 342; break;
    case 343: n = 343; break;
    case 344: n = 344; break;
    case 345: n = 345; break;
    case 346: n = 346; break;
    case 347: n = 347; break;
    case 348: n = 348; break;
    case 349: n = 349; break;
    case 350: n = 350; break;
    case 351: n = 351; break;
    case 352: n = 352; break;
    case 353: n = 353; break;
    case 354: n = 354; break;
    case 355: n = 355; break;
    case 356: n = 356; break;
    case 357: n = 357; break;
    case 358: n = 358; break;
    case 359: n = 359; break;
    case 360: n = 360; break;
    case 361: n = 361; break;
    case 362: n = 362; break;
    case 363: n = 363; break;
    case 364: n = 364; break;
    case 365: n = 365; break;
    case 366: n = 366; break;
    case 367: n = 367; break;
    case 368: n = 368; break;
    case 369: n = 369; break;
    case 370: n = 370; break;
    case 371: n = 371; break;
    case 372: n = 372; break;
    case 373: n = 373; break;
    case 374: n = 374; break;
    case 375: n = 375; break;
    case 376: n = 376; break;
    case 377: n = 377; break;
    case 378: n = 378; break;
    case 379: n = 379; break;
    case 380: n = 380; break;
    case 381: n = 381; break;
    case 382: n = 382; break;
    case 383: n = 383; break;
    case 384: n = 384; break;
    case 385: n = 385; break;
    case 386: n = 386; break;
    case 387: n = 387; break;
    case 388: n = 388; break;
    case 389: n = 389; break;
    case 390: n = 390; break;
    case 391: n = 391; break;
    case 392: n = 392; break;
    case 393: n = 393; break;
    case 394: n = 394; break;
    case 395: n = 395; break;
    case 396: n = 396; break;
    case 397: n = 397; break;
    case 398: n = 398; break;
    case 399: n = 399; break;
    case 400: n = 400; break;
    case 401: n = 401; break;
    case 402: n = 402; break;
    case 403: n = 403; break;
    case 404: n = 404; break;
    case 405: n = 405; break;
    case 406: n = 406; break;
    case 407: n = 407; break;
    case 408: n = 408; break;
    case 409: n = 409; break;
    case 410: n = 410; break;
    case 411: n = 411; break;
    case 412: n = 412; break;
    case 413: n = 413; break;
    case 414: n = 414; break;
    case 415: n = 415; break;
    case 416: n = 416; break;
    case 417: n = 417; break;
    case 418: n = 418; break;
    case 419: n = 419; break;
    case 420: n = 420; break;
    case 421: n = 421; break;
    case 422: n = 422; break;
    case 423: n = 423; break;
    case 424: n = 424; break;
    case 425: n = 425; break;
    case 426: n = 426; break;
    case 427: n = 427; break;
    case 428: n = 428; break;
    case 429: n = 429; break;
    case 430: n = 430; break;
    case 431: n = 431; break;
    case 432: n = 432; break;
    case 433: n = 433; break;
    case 434: n = 434; break;
    case 435: n = 435; break;
    case 436: n = 436; break;
    case 437: n = 437; break;
    case 438: n = 438; break;
    case 439: n = 439; break;
    case 440: n = 440; break;
    case 441: n = 441; break;
    case 442: n = 442; break;
    case 443: n = 443; break;
    case 444: n = 444; break;
    case 445: n = 445; break;
    case 446: n = 446; break;
    case 447: n = 447; break;
    case 448: n = 448; break;
    case 449: n = 449; break;
    case 450: n = 450; break;
    case 451: n = 451; break;
    case 452: n = 452; break;
    case 453: n = 453; break;
    case 454: n = 454; break;
    case 455: n = 455; break;
    case 456: n = 456; break;
    case 457: n = 457; break;
    case 458: n = 458; break;
    case 459: n = 459; break;
    case 460: n = 460; break;
    case 461: n = 461; break;
    case 462: n = 462; break;
    case 463: n = 463; break;
    case 464: n = 464; break;
    case 465: n = 465; break;
    case 466: n = 466; break;
    case 467: n = 467; break;
    case 468: n = 468; break;
    case 469: n = 469; break;
    case 470: n = 470; break;
    case 471: n = 471; break;
    case 472: n = 472; break;
    case 473: n = 473; break;
    case 474: n = 474; break;
    case 475: n = 475; break;
    case 476: n = 476; break;
    case 477: n = 477; break;
    case 478: n = 478; break;
    case 479: n = 479; break;
    case 480: n = 480; break;
    case 481: n = 481; break;
    case 482: n = 482; break;
    case 483: n = 483; break;
    case 484: n = 484; break;
    case 485: n = 485; break;
    case 486: n = 486; break;
    case 487: n = 487; break;
    case 488: n = 488; break;
    case 489: n = 489; break;
    case 490: n = 490; break;
    case 491: n = 491; break;
    case 492: n = 492; break;
    case 493: n = 493; break;
    case 494: n = 494; break;
    case 495: n = 495; break;
    case 496: n = 496; break;
    case 497: n = 497; break;
    case 498: n = 498; break;
    case 499: n = 499; break;
    case 500: n = 500; break;
    case 501: n = 501; break;
    case 502: n = 502; break;
    case 503: n = 503; break;
    case 504: n = 504; break;
    case 505: n = 505; break;
    case 506: n = 506; break;
    case 507: n = 507; break;
    case 508: n = 508; break;
    case 509: n = 509; break;
    case 510: n = 510; break;
    case 511: n = 511; break;
    case 512: n = 512; break;
    case 513: n = 513; break;
    case 514: n = 514; break;
    case 515: n = 515; break;
    case 516: n = 516; break;
    case 517: n = 517; break;
    case 518: n = 518; break;
    case 519: n = 519; break;
    case 520: n = 520; break;
    case 521: n = 521; break;
    case 522: n = 522; break;
    case 523: n = 523; break;
    case 524: n = 524; break;
    case 525: n = 525; break;
    case 526: n = 526; break;
    case 527: n = 527; break;
    case 528: n = 528; break;
    case 529: n = 529; break;
    case 530: n = 530; break;
    case 531: n = 531; break;
    case 532: n = 532; break;
    case 533: n = 533; break;
    case 534: n = 534; break;
    case 535: n = 535; break;
    case 536: n = 536; break;
    case 537: n = 537; break;
    case 538: n = 538; break;
    case 539: n = 539; break;
    case 540: n = 540; break;
    case 541: n = 541; break;
    case 542: n = 542; break;
    case 543: n = 543; break;
    case 544: n = 544; break;
    case 545: n = 545; break;
    case 546: n = 546; break;
    case 547: n = 547; break;
    case 548: n = 548; break;
    case 549: n = 549; break;
    case 550: n = 550; break;
    case 551: n = 551; break;
    case 552: n = 552; break;
    case 553: n = 553; break;
    case 554: n = 554; break;
    case 555: n = 555; break;
    case 556: n = 556; break;
    case 557: n = 557; break;
    case 558: n = 558; break;
    case 559: n = 559; break;
    case 560: n = 560; break;
    case 561: n = 561; break;
    case 562: n = 562; break;
    case 563: n = 563; break;
    case 564: n = 564; break;
    case 565: n = 565; break;
    case 566: n = 566; break;
    case 567: n = 567; break;
    case 568: n = 568; break;
    case 569: n = 569; break;
    case 570: n = 570; break;
    case 571: n = 571; break;
    case 572: n = 572; break;
    case 573: n = 573; break;
    case 574: n = 574; break;
    case 575: n = 575; break;
    case 576: n = 576; break;
    case 577: n = 577; break;
    case 578: n = 578; break;
    case 579: n = 579; break;
    case 580: n = 580; break;
    case 581: n = 581; break;
    case 582: n = 582; break;
    case 583: n = 583; break;
    case 584: n = 584; break;
    case 585: n = 585; break;
    case 586: n = 586; break;
    case 587: n = 587; break;
    case 588: n = 588; break;
    case 589: n = 589; break;
    case 590: n = 590; break;
    case 591: n = 591; break;
    case 592: n = 592; break;
    case 593: n = 593; break;
    case 594: n = 594; break;
    case 595: n = 595; break;
    case 596: n = 596; break;
    case 597: n = 597; break;
    case 598: n = 598; break;
    case 599: n = 599; break;
    case 600: n = 600; break;
    case 601: n = 601; break;
    case 602: n = 602; break;
    case 603: n = 603; break;
    case 604: n = 604; break;
    case 605: n = 605; break;
    case 606: n = 606; break;
    case 607: n = 607; break;
    case 608: n = 608; break;
    case 609: n = 609; break;
    case 610: n = 610; break;
    case 611: n = 611; break;
    case 612: n = 612; break;
    case 613: n = 613; break;
    case 614: n = 614; break;
    case 615: n = 615; break;
    case 616: n = 616; break;
    case 617: n = 617; break;
    case 618: n = 618; break;
    case 619: n = 619; break;
    case 620: n = 620; break;
    case 621: n = 621; break;
    case 622: n = 622; break;
    case 623: n = 623; break;
    case 624: n = 624; break;
    case 625: n = 625; break;
    case 626: n = 626; break;
    case 627: n = 627; break;
    case 628: n = 628; break;
    case 629: n = 629; break;
    case 630: n = 630; break;
    case 631: n = 631; break;
    case 632: n = 632; break;
    case 633: n = 633; break;
    case 634: n = 634; break;
    case 635: n = 635; break;
    case 636: n = 636; break;
    case 637: n = 637; break;
    case 638: n = 638; break;
    case 639: n = 639; break;
    case 640: n = 640; break;
    case 641: n = 641; break;
    case 642: n = 642; break;
    case 643: n = 643; break;
    case 644: n = 644; break;
    case 645: n = 645; break;
    case 646: n = 646; break;
    case 647: n = 647; break;
    case 648: n = 648; break;
    case 649: n = 649; break;
    case 650: n = 650; break;
    case 651: n = 651; break;
    case 652: n = 652; break;
    case 653: n = 653; break;
    case 654: n = 654; break;
    case 655: n = 655; break;
    case 656: n = 656; break;
    case 657: n = 657; break;
    case 658: n = 658; break;
    case 659: n = 659; break;
    case 660: n = 660; break;
    case 661: n = 661; break;
    case 662: n = 662; break;
    case 663: n = 663; break;
    case 664: n = 664; break;
    case 665: n = 665; break;
    case 666: n = 666; break;
    case 667: n = 667; break;
    case 668: n = 668; break;
    case 669: n = 669; break;
    case 670: n = 670; break;
    case 671: n = 671; break;
    case 672: n = 672; break;
    case 673: n = 673; break;
    case 674: n = 674; break;
    case 675: n = 675; break;
    case 676: n = 676; break;
    case 677: n = 677; break;
    case 678: n = 678; break;
    case 679: n = 679; break;
    case 680: n = 680; break;
    case 681: n = 681; break;
    case 682: n = 682; break;
    case 683: n = 683; break;
    case 684: n = 684; break;
    case 685: n = 685; break;
    case 686: n = 686; break;
    case 687: n = 687; break;
    case 688: n = 688; break;
    case 689: n = 689; break;
    case 690: n = 690; break;
    case 691: n = 691; break;
    case 692: n = 692; break;
    case 693: n = 693; break;
    case 694: n = 694; break;
    case 695: n = 695; break;
    case 696: n = 696; break;
    case 697: n = 697; break;
    case 698: n = 698; break;
    case 699: n = 699; break;
    case 700: n = 700; break;
    case 701: n = 701; break;
    case 702: n = 702; break;
    case 703: n = 703; break;
    case 704: n = 704; break;
    case 705: n = 705; break;
    case 706: n = 706; break;
    case 707: n = 707; break;
    case 708: n = 708; break;
    case 709: n = 709; break;
    case 710: n = 710; break;
    case 711: n = 711; break;
    case 712: n = 712; break;
    case 713: n = 713; break;
    case 714: n = 714; break;
    case 715: n = 715; break;
    case 716: n = 716; break;
    case 717: n = 717; break;
    case 718: n = 718; break;
    case 719: n = 719; break;
    case 720: n = 720; break;
    case 721: n = 721; break;
    case 722: n = 722; break;
    case 723: n = 723; break;
    case 724: n = 724; break;
    case 725: n = 725; break;
    case 726: n = 726; break;
    case 727: n = 727; break;
    case 728: n = 728; break;
    case 729: n = 729; break;
    case 730: n = 730; break;
    case 731: n = 731; break;
    case 732: n = 732; break;
    case 733: n = 733; break;
    case 734: n = 734; break;
    case 735: n = 735; break;
    case 736: n = 736; break;
    case 737: n = 737; break;
    case 738: n = 738; break;
    case 739: n = 739; break;
    case 740: n = 740; break;
    case 741: n = 741; break;
    case 742: n = 742; break;
    case 743: n = 743; break;
    case 744: n = 744; break;
    case 745: n = 745; break;
    case 746: n = 746; break;
    case 747: n = 747; break;
    case 748: n = 748; break;
    case 749: n = 749; break;
    case 750: n = 750; break;
    case 751: n = 751; break;
    case 752: n = 752; break;
    case 753: n = 753; break;
    case 754: n = 754; break;
    case 755: n = 755; break;
    case 756: n = 756; break;
    case 757: n = 757; break;
    case 758: n = 758; break;
    case 759: n = 759; break;
    case 760: n = 760; break;
    case 761: n = 761; break;
    case 762: n = 762; break;
    case 763: n = 763; break;
    case 764: n = 764; break;
    case 765: n = 765; break;
    case 766: n = 766; break;
    case 767: n = 767; break;
    case 768: n = 768; break;
    case 769: n = 769; break;
    case 770: n = 770; break;
    case 771: n = 771; break;
    case 772: n = 772; break;
    case 773: n = 773; break;
    case 774: n = 774; break;
    case 775: n = 775; break;
    case 776: n = 776; break;
    case 777: n = 777; break;
    case 778: n = 778; break;
    case 779: n = 779; break;
    case 780: n = 780; break;
    case 781: n = 781; break;
    case 782: n = 782; break;
    case 783: n = 783; break;
    case 784: n = 784; break;
    case 785: n = 785; break;
    case 786: n = 786; break;
    case 787: n = 787; break;
    case 788: n = 788; break;
    case 789: n = 789; break;
    case 790: n = 790; break;
    case 791: n = 791; break;
    case 792: n = 792; break;
    case 793: n = 793; break;
    case 794: n = 794; break;
    case 795: n = 795; break;
    case 796: n = 796; break;
    case 797: n = 797; break;
    case 798: n = 798; break;
    case 799: n = 799; break;
    case 800: n = 800; break;
    case 801: n = 801; break;
    case 802: n = 802; break;
    case 803: n = 803; break;
    case 804: n = 804; break;
    case 805: n = 805; break;
    case 806: n = 806; break;
    case 807: n = 807; break;
    case 808: n = 808; break;
    case 809: n = 809; break;
    case 810: n = 810; break;
    case 811: n = 811; break;
    case 812: n = 812; break;
    case 813: n = 813; break;
    case 814: n = 814; break;
    case 815: n = 815; break;
    case 816: n = 816; break;
    case 817: n = 817; break;
    case 818: n = 818; break;
    case 819: n = 819; break;
    case 820: n = 820; break;
    case 821: n = 821; break;
    case 822: n = 822; break;
    case 823: n = 823; break;
    case 824: n = 824; break;
    case 825: n = 825; break;
    case 826: n = 826; break;
    case 827: n = 827; break;
    case 828: n = 828; break;
    case 829: n = 829; break;
    case 830: n = 830; break;
    case 831: n = 831; break;
    case 832: n = 832; break;
    case 833: n = 833; break;
    case 834: n = 834; break;
    case 835: n = 835; break;
    case 836: n = 836; break;
    case 837: n = 837; break;
    case 838: n = 838; break;
    case 839: n = 839; break;
    case 840: n = 840; break;
    case 841: n = 841; break;
    case 842: n = 842; break;
    case 843: n = 843; break;
    case 844: n = 844; break;
    case 845: n = 845; break;
    case 846: n = 846; break;
    case 847: n = 847; break;
    case 848: n = 848; break;
    case 849: n = 849; break;
    case 850: n = 850; break;
    case 851: n = 851; break;
    case 852: n = 852; break;
    case 853: n = 853; break;
    case 854: n = 854; break;
    case 855: n = 855; break;
    case 856: n = 856; break;
    case 857: n = 857; break;
    case 858: n = 858; break;
    case 859: n = 859; break;
    case 860: n = 860; break;
    case 861: n = 861; break;
    case 862: n = 862; break;
    case 863: n = 863; break;
    case 864: n = 864; break;
    case 865: n = 865; break;
    case 866: n = 866; break;
    case 867: n = 867; break;
    case 868: n = 868; break;
    case 869: n = 869; break;
    case 870: n = 870; break;
    case 871: n = 871; break;
    case 872: n = 872; break;
    case 873: n = 873; break;
    case 874: n = 874; break;
    case 875: n = 875; break;
    case 876: n = 876; break;
    case 877: n = 877; break;
    case 878: n = 878; break;
    case 879: n = 879; break;
    case 880: n = 880; break;
    case 881: n = 881; break;
    case 882: n = 882; break;
    case 883: n = 883; break;
    case 884: n = 884; break;
    case 885: n = 885; break;
    case 886: n = 886; break;
    case 887: n = 887; break;
    case 888: n = 888; break;
    case 889: n = 889; break;
    case 890: n = 890; break;
    case 891: n = 891; break;
    case 892: n = 892; break;
    case 893: n = 893; break;
    case 894: n = 894; break;
    case 895: n = 895; break;
    case 896: n = 896; break;
    case 897: n = 897; break;
    case 898: n = 898; break;
    case 899: n = 899; break;
    case 900: n = 900; break;
    case 901: n = 901; break;
    case 902: n = 902; break;
    case 903: n = 903; break;
    case 904: n = 904; break;
    case 905: n = 905; break;
    case 906: n = 906; break;
    case 907: n = 907; break;
    case 908: n = 908; break;
    case 909: n = 909; break;
    case 910: n = 910; break;
    case 911: n = 911; break;
    case 912: n = 912; break;
    case 913: n = 913; break;
    case 914: n = 914; break;
    case 915: n = 915; break;
    case 916: n = 916; break;
    case 917: n = 917; break;
    case 918: n = 918; break;
    case 919: n = 919; break;
    case 920: n = 920; break;
    case 921: n = 921; break;
    case 922: n = 922; break;
    case 923: n = 923; break;
    case 924: n = 924; break;
    case 925: n = 925; break;
    case 926: n = 926; break;
    case 927: n = 927; break;
    case 928: n = 928; break;
    case 929: n = 929; break;
    case 930: n = 930; break;
    case 931: n = 931; break;
    case 932: n = 932; break;
    case 933: n = 933; break;
    case 934: n = 934; break;
    case 935: n = 935; break;
    case 936: n = 936; break;
    case 937: n = 937; break;
    case 938: n = 938; break;
    case 939: n = 939; break;
    case 940: n = 940; break;
    case 941: n = 941; break;
    case 942: n = 942; break;
    case 943: n = 943; break;
    case 944: n = 944; break;
    case 945: n = 945; break;
    case 946: n = 946; break;
    case 947: n = 947; break;
    case 948: n = 948; break;
    case 949: n = 949; break;
    case 950: n = 950; break;
    case 951: n = 951; break;
    case 952: n = 952; break;
    case 953: n = 953; break;
    case 954: n = 954; break;
    case 955: n = 955; break;
    case 956: n = 956; break;
    case 957: n = 957; break;
    case 958: n = 958; break;
    case 959: n = 959; break;
    case 960: n = 960; break;
    case 961: n = 961; break;
    case 962: n = 962; break;
    case 963: n = 963; break;
    case 964: n = 964; break;
    case 965: n = 965; break;
    case 966: n = 966; break;
    case 967: n = 967; break;
    case 968: n = 968; break;
    case 969: n = 969; break;
    case 970: n = 970; break;
    case 971: n = 971; break;
    case 972: n = 972; break;
    case 973: n = 973; break;
    case 974: n = 974; break;
    case 975: n = 975; break;
    case 976: n = 976; break;
    case 977: n = 977; break;
    case 978: n = 978; break;
    case 979: n = 979; break;
    case 980: n = 980; break;
    case 981: n = 981; break;
    case 982: n = 982; break;
    case 983: n = 983; break;
    case 984: n = 984; break;
    case 985: n = 985; break;
    case 986: n = 986; break;
    case 987: n = 987; break;
    case 988: n = 988; break;
    case 989: n = 989; break;
    case 990: n = 990; break;
    case 991: n = 991; break;
    case 992: n = 992; break;
    case 993: n = 993; break;
    case 994: n = 994; break;
    case 995: n = 995; break;
    case 996: n = 996; break;
    case 997: n = 997; break;
    case 998: n = 998; break;
    case 999: n = 999; break;
    case 1000: n = 1000; break;
    case 1001: n = 1001; break;
    case 1002: n = 1002; break;
    case 1003: n = 1003; break;
    case 1004: n = 1004; break;
    case 1005: n = 1005; break;
    case 1006: n = 1006; break;
    case 1007: n = 1007; break;
    case 1008: n = 1008; break;
    case 1009: n = 1009; break;
    case 1010: n = 1010; break;
    case 1011: n = 1011; break;
    case 1012: n = 1012; break;
    case 1013: n = 1013; break;
    case 1014: n = 1014; break;
    case 1015: n = 1015; break;
    case 1016: n = 1016; break;
    case 1017: n = 1017; break;
    case 1018: n = 1018; break;
    case 1019: n = 1019; break;
    case 1020: n = 1020; break;
    case 1021: n = 1021; break;
    case 1022: n = 1022; break;
    default: n = -1; break;
    }
    return n;
}

static int sec_03_translation_limits(void)
{
    int failures = g_fail;

    sec_begin("03 translation limits");

    CHECK(C99_LIMIT_MACRO_0000 == 0);
    CHECK(C99_LIMIT_MACRO_2047 == 2047);
    CHECK(C99_LIMIT_MACRO_4094 == 4094);
    CHECK(sizeof c99_long_literal == 4096);
    CHECK(strlen(c99_long_literal) == 4095);
    CHECK(sizeof c99_long_concatenated == 4096);
    CHECK(strlen(c99_long_concatenated) == 4095);
#ifdef C99_OVERLONG_STRINGS
    /* Past the 4095-character minimum the standard guarantees (C99 5.2.4.1);
     * enabling these needs -Wno-overlength-strings. */
    CHECK(c99_overlong_literal[0] == '0');
    CHECK(strlen(c99_overlong_literal) == sizeof c99_overlong_literal - 1);
    CHECK(strlen(c99_overlong_literal) >= 4095);
    CHECK(strlen(c99_overlong_concatenated) ==
          sizeof c99_overlong_concatenated - 1);
    CHECK(strlen(c99_overlong_concatenated) >= 4095);
    CHECK(c99_overlong_concatenated[0] == 'a');
#endif
    CHECK(sizeof c99_large_object == 40000);
    c99_large_object[39999] = 0x5A;
    CHECK(c99_large_object[39999] == 0x5A);
    CHECK(c99_internal_identifier_name_of_exactly_sixty_three_chars_abcde_one == 11);
    CHECK(c99_internal_identifier_name_of_exactly_sixty_three_chars_abcde_two == 22);
    CHECK(c99_deep_parens() == 42);
    CHECK(c99_deep_blocks() == 127);
    CHECK(c99_nested_conditional() == 63);
    CHECK(c99_many_params(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127) == 8128);
    CHECK(c99_call_many_params() == 8128);
    CHECK(c99_twelve_level_pointer() == 5);
    CHECK(c99_many_block_identifiers() == 130305);
    CHECK(sizeof(struct c99_wide_struct) == 1023 * sizeof(int));
    CHECK(sizeof(union c99_wide_union) == sizeof(int));
    CHECK(C99_ENUM_0000 == 0);
    CHECK(C99_ENUM_1022 == 1022);
    CHECK(c99_many_cases(0) == 0);
    CHECK(c99_many_cases(512) == 512);
    CHECK(c99_many_cases(1022) == 1022);
    CHECK(c99_many_cases(-1) == -1);

    return g_fail - failures;
}

/* ==========================================================================
 * 04 declarations, scopes, storage classes
 * ========================================================================== */

static int c99_file_scope_object = 100;      /* static storage duration */
extern int c99_file_scope_object;            /* extern declaration of it */
static int c99_tentative_definition;         /* tentative definition */
static const int c99_const_object = 7;
static volatile int c99_volatile_object = 1;
static int c99_static_array[4] = {1, 2};     /* the rest are zeroed */

typedef unsigned long c99_ulong_t;
typedef int c99_array3_t[3];
typedef int (*c99_binop_t)(int, int);
typedef struct c99_pair { int a, b; } c99_pair_t;   /* tag and typedef */

/* Incomplete type completed later, used through a pointer meanwhile. */
struct c99_fwd;
static struct c99_fwd *c99_fwd_ptr;
struct c99_fwd { int member; };

/* Function definitions may carry the same parameter names as other functions;
 * declarations are block-scope entities in C99 (no nested functions). */
static int c99_add(int x, int y) { return x + y; }
static int c99_mul(int x, int y) { return x * y; }

/* restrict may be applied through a typedef of a pointer type (C99 6.7.3). */
typedef int *c99_intptr_t;
static int c99_sum_restrict(int n, c99_intptr_t restrict p)
{
    int total = 0;
    for (int i = 0; i < n; ++i) {
        total += p[i];
    }
    return total;
}

static int sec_04_declarations(void)
{
    int failures = g_fail;
    int before = c99_file_scope_object;  /* mixed: declarations and code */
    before += 1;
    long after = before * 2L;            /* declared after a statement */
    int i = 0;
    c99_array3_t arr3 = {10, 20, 30};
    c99_pair_t pair = {1, 2};
    c99_binop_t ops[2];
    struct c99_fwd fwd = {5};
    c99_intptr_t p;
    int numbers[4] = {4, 5, 6, 7};

    sec_begin("04 declarations, scopes, storage classes");

    for (int loop_var = 0; loop_var < 3; ++loop_var) { /* C99 for-decl */
        i += loop_var;
    }
    CHECK(i == 3);

    CHECK(before == 101 && after == 202L);
    CHECK(c99_file_scope_object == 100);
    CHECK(c99_tentative_definition == 0);
    CHECK(c99_const_object == 7);
    c99_volatile_object = 2;
    CHECK(c99_volatile_object == 2);
    CHECK(c99_static_array[0] == 1 && c99_static_array[1] == 2);
    CHECK(c99_static_array[2] == 0 && c99_static_array[3] == 0);
    CHECK(arr3[0] == 10 && arr3[2] == 30 && sizeof arr3 == 3 * sizeof(int));
    CHECK(pair.a == 1 && pair.b == 2);
    CHECK(fwd.member == 5);
    c99_fwd_ptr = &fwd;
    CHECK(c99_fwd_ptr->member == 5);

    ops[0] = c99_add;
    ops[1] = c99_mul;
    CHECK(ops[0](3, 4) == 7);
    CHECK(ops[1](3, 4) == 12);

    p = numbers;
    CHECK(c99_sum_restrict(4, p) == 22);
    CHECK(p[3] == 7 && *(p + 3) == 7 && 3[p] == 7);

    {                                  /* nested block scope */
        int before = 1000;             /* shadows the outer object */
        CHECK(before == 1000);
        CHECK(c99_file_scope_object == 100);
        {
            int before = 2000;         /* shadow again, two levels deep */
            CHECK(before == 2000 && i == 3);
        }
    }
    CHECK(before == 101);

    {                                  /* block-scope tag and typedef */
        struct c99_pair { long x, y; };      /* shadows the file-scope tag */
        typedef struct c99_pair inner_pair;  /* block-scope typedef */
        inner_pair ip = {3L, 4L};
        enum c99_local_enum { LOCAL_A = 5, LOCAL_B, LOCAL_C };
        CHECK(sizeof(inner_pair) == 2 * sizeof(long));
        CHECK(ip.x == 3L && ip.y == 4L);
        CHECK(LOCAL_A + LOCAL_B + LOCAL_C == 18);
    }

    {                                  /* storage-class specifiers */
        auto int auto_var = 3;         /* auto: no effect, still valid */
        static int static_local = 0;
        extern int c99_file_scope_object;   /* redundant extern declaration */
        ++static_local;
        CHECK(auto_var == 3);
        CHECK(static_local == 1);
        CHECK(c99_file_scope_object == 100);
    }

    /* register objects may not have their address taken; this one is used. */
    { register int reg = 4; CHECK(reg * 2 == 8); }

    /* A typedef of a variable-length array type (C99 6.7.5.2).  A VLA may not
     * be initialized, so the elements are assigned one at a time. */
    {
        int n = 3;
        typedef int c99_vla_t[n];
        c99_vla_t vla;         /* no initializer is allowed for a VLA */
        vla[0] = 1;
        vla[1] = 2;
        vla[2] = 3;
        CHECK(sizeof(c99_vla_t) == 3 * sizeof(int));
        CHECK(sizeof vla == sizeof(c99_vla_t));
        CHECK(vla[0] + vla[1] + vla[2] == 6);
    }

    /* sizeof forms: type, expression, parenthesized expression. */
    CHECK(sizeof(int) == sizeof i);
    CHECK(sizeof numbers == 4 * sizeof(int));
    CHECK(sizeof p == sizeof(void *));
    CHECK(sizeof "abc" == 4);
    CHECK(sizeof(struct c99_fwd) == sizeof(int));
    CHECK(offsetof(c99_pair_t, b) == sizeof(int));

    return g_fail - failures;
}

/* ==========================================================================
 * 05 types
 * ========================================================================== */

static int sec_05_types(void)
{
    int failures = g_fail;

    _Bool b_from_int = 42;
    _Bool b_from_zero = 0;
    unsigned long long ull_source = 1ULL << 40;
    _Bool b_from_ull = ull_source;
    int target_for_bool = 1;
    int *ptr_for_bool = &target_for_bool;
    _Bool b_from_ptr = ptr_for_bool;
    bool std_bool = true;
    bool std_bool_false = false;
    unsigned char uc = 255;
    signed char sc = -128;
    short sh = SHRT_MIN;
    unsigned short ush = USHRT_MAX;
    long lo = LONG_MAX;
    unsigned long ul = ULONG_MAX;
    long long ll = LLONG_MIN;
    unsigned long long ull = ULLONG_MAX;
    long double ld = 1.5L;
    float f = 1.5f;
    double d = 1.5;
    int8_t i8 = INT8_MIN;
    uint8_t u8 = UINT8_MAX;
    int16_t i16 = INT16_MAX;
    uint16_t u16 = UINT16_MAX;
    int32_t i32 = INT32_MIN;
    uint32_t u32 = UINT32_MAX;
    int64_t i64 = INT64_MAX;
    uint64_t u64 = UINT64_MAX;
    int_least8_t l8 = INT_LEAST8_MAX;
    uint_least16_t l16 = UINT_LEAST16_MAX;
    int_fast8_t f8 = INT_FAST8_MAX;
    uint_fast32_t f32 = UINT_FAST32_MAX;
    intmax_t imax = INTMAX_MAX;
    uintmax_t umax = UINTMAX_MAX;
    intptr_t iptr = INT8_C(0);
    size_t sz = SIZE_MAX;
    ptrdiff_t pd = PTRDIFF_MAX;
    wchar_t wc = L'x';
    wint_t wi = WINT_MAX;
    sig_atomic_t sa = SIG_ATOMIC_MAX;
    const int *pci = &c99_const_object;
    int *const cpi = &c99_tentative_definition;
    volatile const int vci = 3;
    struct c99_bitfield {
        unsigned int a : 3;   /* unsigned bitfield */
        signed int b : 5;     /* signed bitfield */
        _Bool c : 1;          /* _Bool bitfield is a C99 addition */
        unsigned int : 0;     /* unnamed zero-width bitfield: alignment */
        unsigned int d : 2;
    } bf = {5u, -3, 1, 1u};

    sec_begin("05 types");

    CHECK(b_from_int == 1);
    CHECK(b_from_zero == 0);
    CHECK(b_from_ull == 1);
    CHECK(b_from_ptr == 1);
    CHECK((_Bool)256 == 1);
    CHECK((_Bool)0.0 == 0);
    CHECK((_Bool)-0.5 == 1);
    CHECK(sizeof(_Bool) == 1);
    CHECK(__bool_true_false_are_defined == 1);
    CHECK(std_bool && !std_bool_false);

    CHECK(uc == 255u && sc == -128 && sizeof(char) == 1);
    CHECK(sh == SHRT_MIN && ush == USHRT_MAX);
    CHECK(lo == LONG_MAX && ul == ULONG_MAX);
    CHECK(CHAR_BIT >= 8 && CHAR_MIN <= 0);
    CHECK(sizeof(short) >= 2 && sizeof(int) >= 2 && sizeof(long) >= 4);
    CHECK(sizeof(long long) >= 8);
    CHECK(ll == LLONG_MIN && ull == ULLONG_MAX);
    CHECK(LLONG_MAX > LONG_MAX || sizeof(long long) == sizeof(long));

    CHECK(sizeof(float) <= sizeof(double));
    CHECK(sizeof(double) <= sizeof(long double));
    CHECK(f == 1.5f && d == 1.5 && ld == 1.5L);
    CHECK(sizeof ld == sizeof(long double) && sizeof f == sizeof(float));
    CHECK(c99_nearlyl(sqrtl(2.0L) * sqrtl(2.0L), 2.0L));
    CHECK(FLT_RADIX >= 2 && FLT_MANT_DIG > 0 && DBL_MANT_DIG > FLT_MANT_DIG);
    CHECK(FLT_EVAL_METHOD >= -1 && FLT_ROUNDS >= -1);
    CHECK(DECIMAL_DIG >= 9);
    CHECK(DBL_DIG > FLT_DIG && LDBL_DIG >= DBL_DIG);

    CHECK(i8 == INT8_MIN && u8 == UINT8_MAX && sizeof(i8) == 1);
    CHECK(i16 == INT16_MAX && u16 == UINT16_MAX && sizeof(u16) == 2);
    CHECK(i32 == INT32_MIN && u32 == UINT32_MAX && sizeof(u32) == 4);
    CHECK(i64 == INT64_MAX && u64 == UINT64_MAX && sizeof(u64) == 8);
    CHECK(l8 == INT_LEAST8_MAX && l16 == UINT_LEAST16_MAX);
    CHECK(f8 == INT_FAST8_MAX && f32 == UINT_FAST32_MAX);
    CHECK(imax == INTMAX_MAX && umax == UINTMAX_MAX);
    CHECK(sizeof(intmax_t) >= sizeof(long long));
    CHECK(INTMAX_C(1) == 1 && UINTMAX_C(1) == 1u);
    CHECK(INT8_C(1) == 1 && UINT8_C(1) == 1u);
    CHECK(INT64_C(1) == 1 && UINT64_C(1) == 1ull);

    /* Object/pointer round trips through the smallest and widest ints. */
    {
        int target = 1234;
        uintptr_t as_int = (uintptr_t)&target;
        void *as_ptr = (void *)as_int;
        intptr_t signed_int = (intptr_t)as_ptr;
        int *recovered = (int *)(void *)signed_int;
        CHECK(*(int *)as_ptr == 1234);
        CHECK(*recovered == 1234);
        CHECK((void *)&target == (void *)as_ptr);
        CHECK(iptr == 0);
    }

    CHECK(sz == SIZE_MAX && sizeof(size_t) == sizeof(void *));
    CHECK(pd == PTRDIFF_MAX && sizeof(ptrdiff_t) == sizeof(void *));
    CHECK(PTRDIFF_MIN < 0);
    CHECK(wc == L'x' && sizeof(wchar_t) >= 1);
    CHECK(WCHAR_MIN <= 0 && WCHAR_MAX > 127);
    CHECK(wi == WINT_MAX && WINT_MIN <= 0);
    CHECK(sa == SIG_ATOMIC_MAX && SIG_ATOMIC_MIN <= 0);
    CHECK(INT8_MIN < 0 && INT16_MIN < 0 && INT32_MIN < 0 && INT64_MIN < 0);
    CHECK(INT_LEAST8_MIN < 0 && INT_FAST8_MIN < 0);

    /* Qualified types. */
    CHECK(*pci == 7);
    *cpi = 9;
    CHECK(c99_tentative_definition == 9);
    CHECK(vci == 3);
    CHECK(sizeof(const int) == sizeof(int));
    CHECK(sizeof(volatile int) == sizeof(int));

    /* Bitfields. */
    CHECK(bf.a == 5u && bf.c == 1u && bf.d == 1u);
    CHECK(sizeof(struct c99_bitfield) >= 2);

    /* enum: C99 allows a trailing comma and values beyond int range. */
    {
        enum c99_small { SMALL_ONE = 1, SMALL_TWO, SMALL_THREE, } e = SMALL_TWO;
        enum c99_neg { NEG_MIN = -3, NEG_ZERO = 0, NEG_POS = 3 };
        enum c99_big { BIG = 65535 };
        CHECK(e == 2 && SMALL_THREE == 3);
        CHECK(NEG_MIN + NEG_POS == 0 && NEG_ZERO == 0);
        CHECK(BIG == 65535);
        CHECK(sizeof e == sizeof(int));
    }

    return g_fail - failures;
}

/* ==========================================================================
 * 06 expressions and conversions
 * ========================================================================== */

static int c99_side_effects;
static int c99_bump(void) { return ++c99_side_effects; }

/* Precedence probes that would trip -Wparentheses in C source.  The
 * preprocessor applies the same operator precedence and neither GCC nor Clang
 * warns about it there, so the unparenthesized forms are checked here. */
#if 1 << 2 + 1 != 8
#error "shift binds looser than additive +"
#endif
#if (1 + 2) * 3 != 9
#error "parentheses override precedence"
#endif
#if 4 % 3 * 2 != 2
#error "multiplicative operators are left associative"
#endif
#define C99_SHIFT_ADD_PRECEDENCE (2 + 1)   /* preprocessor-verified equivalent */

/* Declared before use: C99 removed the implicit int / implicit declaration of
 * C90, so every call needs a visible prototype. */
static int c99_uc_roundtrip_probe(int value);

static int sec_06_expressions(void)
{
    int failures = g_fail;
    int a = 7, b = 2, c = -7;
    unsigned int u = 1u;
    double d = 3.75;
    char ch = 'A';
    long long ll = 4000000000LL;
    int arr[5] = {0, 10, 20, 30, 40};
    int *p = arr;
    int **pp = &p;
    struct c99_pair pair = {3, 4};
    struct c99_pair *ppair = &pair;
    sec_begin("06 expressions and conversions");

    /* Unary operators. */
    CHECK(+a == 7 && -a == -7 && (!a) == 0 && (!!a) == 1);
    CHECK(~0 == -1 && ~a == -8);
    CHECK(&pair == ppair && ppair->a == 3 && pair.b == 4);
    CHECK(*p == 0 && p[2] == 20 && *(p + 3) == 30);
    CHECK(sizeof p == sizeof(int *));

    /* Increment and decrement, pre and post. */
    {
        int n = 5;
        CHECK(n++ == 5 && n == 6);
        CHECK(++n == 7);
        CHECK(n-- == 7 && n == 6);
        CHECK(--n == 5);
    }

    /* Binary arithmetic, precedence, associativity. */
    CHECK(2 + 3 * 4 == 14);
    CHECK((2 + 3) * 4 == 20);
    CHECK(7 / 2 == 3 && 7 % 2 == 1);
    CHECK(c / b == -3 && c % b == -1);        /* C99: division truncates */
    CHECK(-7 / 2 == -3 && -7 % 2 == -1);
    CHECK(2 - 3 - 4 == -5);                   /* left associative */
    /* Parenthesized precedence probes.  The unparenthesized forms are probed
     * by the preprocessor below, where the same precedence rules apply and no
     * -Wparentheses diagnostic exists. */
    CHECK((1 << 2) + 1 == 5);
    CHECK((256 >> 2) == 64 && ((unsigned)-1 >> 1) == 2147483647u);
    CHECK(1 << C99_SHIFT_ADD_PRECEDENCE == 8);
    CHECK((6 & 3) == 2 && (6 | 3) == 7 && (6 ^ 3) == 5);
    CHECK(2 + 3 == 5 && 2 != 3 && 2 < 3 && 3 > 2 && 2 <= 2 && 3 >= 3);
    CHECK((1 && 2) == 1 && (0 || 3) == 1 && (0 && 3) == 0);
    CHECK((a > b ? a : b) == 7);
    CHECK((a > b ? (b > 0 ? 1 : 2) : 3) == 1);
    CHECK((a = 1, b = 2, a + b) == 3);        /* comma operator */
    CHECK((a += 1) == 2 && (a -= 1) == 1 && (a *= 5) == 5);
    CHECK((a /= 2) == 2 && (a %= 2) == 0 && (a -= 0) == 0);
    CHECK((a = 1u << 3) == 8 && (a <<= 1) == 16 && (a >>= 2) == 4);
    CHECK((a &= 6) == 4 && (a |= 3) == 7 && (a ^= 1) == 6);
    CHECK((a = b = 3) == 3 && a == 3 && b == 3);   /* right associative = */

    /* Casts. */
    CHECK((int)3.9 == 3 && (int)-3.9 == -3 && (int)0.5 == 0);
    CHECK((double)1 / 3 != 0.0);
    CHECK((float)1.0 == 1.0f && (long double)1.0 == 1.0L);
    CHECK((char)(ch + 1) == 'B' && (int)ch == 65);
    CHECK((unsigned char)c99_uc_roundtrip_probe(300) == 44);
    CHECK(((long long)1 << 32) > 0);
    {
        int dummy = 0;
        CHECK((dummy = 1, dummy) == 1);      /* comma operator, sequenced */
        (void)c99_bump();                    /* cast to void as a statement */
        CHECK(c99_side_effects == 1);
        c99_side_effects = 0;
    }
    CHECK((int)(uintptr_t)(void *)&a != 0);

    /* Usual arithmetic conversions and promotions. */
    CHECK(sizeof((char)1 + (char)2) == sizeof(int));
    CHECK((char)1 + (char)2 == 3);
    {
        int minus_one = -1;
        unsigned int from_negative = minus_one;    /* -1 wraps to UINT_MAX */
        unsigned int from_cast = (unsigned)-1;
        CHECK(from_negative == UINT_MAX);
        CHECK(from_cast == from_negative);
        CHECK(from_negative + 1u == 0u);
        CHECK(from_negative > 0u);
    }
    CHECK((double)7 / 2 == 3.5);
    CHECK((double)a / 2 == 1.5);              /* a was set to 3 just above */
    CHECK((float)(1.0 / 3.0) != 1.0 / 3.0 || sizeof(float) == sizeof(double));
    CHECK((long double)ll == 4000000000.0L);
    CHECK(d * 4 == 15.0);
    CHECK(u + 1u == 2u);

    /* Short-circuit evaluation: the right operand must not run. */
    c99_side_effects = 0;
    CHECK((0 && c99_bump()) == 0 && c99_side_effects == 0);
    CHECK((1 || c99_bump()) == 1 && c99_side_effects == 0);
    CHECK((1 && c99_bump()) == 1 && c99_side_effects == 1);
    CHECK((0 || c99_bump()) == 1 && c99_side_effects == 2);
    CHECK(c99_bump() == 3);

    /* Conditional operator: only one arm is evaluated, and the result type
     * follows the usual arithmetic conversions of both arms. */
    CHECK((c99_side_effects == 3 ? 1 : c99_bump()) == 1);
    CHECK(c99_side_effects == 3);
    CHECK(sizeof(1 ? 1 : 1.0) == sizeof(double));

    /* Pointer arithmetic and comparison. */
    CHECK(p + 4 == &arr[4] && &arr[4] - p == 4);
    CHECK(p < p + 1 && p + 1 > p && p == &arr[0] && p != NULL);
    CHECK((void *)0 == NULL);
    CHECK(*pp == p && **pp == 0);
    {
        int (*row)[5] = &arr;
        CHECK((*row)[1] == 10 && sizeof *row == 5 * sizeof(int));
    }

    /* Casting between function pointer types and back (C99 6.3.2.3). */
    {
        int (*fp)(int, int) = c99_add;
        void (*generic)(void) = (void (*)(void))fp;
        c99_binop_t back = (c99_binop_t)generic;
        CHECK(back(20, 22) == 42);
        CHECK((*fp)(1, 2) == 3);
    }

    return g_fail - failures;
}

/* ==========================================================================
 * 07 control flow
 * ========================================================================== */

static int c99_uc_roundtrip_probe(int value)
{
    return value & 0xFF;
}

static int sec_07_control_flow(void)
{
    int failures = g_fail;
    int n = 0;
    int i = 0;
    int j = 0;

    sec_begin("07 control flow");

    /* if / else if / else. */
    for (i = 0; i < 3; ++i) {
        if (i == 0) {
            n += 1;
        } else if (i == 1) {
            n += 2;
        } else {
            n += 3;
        }
    }
    CHECK(n == 6);

    /* Nearest-if binding.  The ambiguous (unbraced) form is exactly what
     * -Wdangling-else flags, so the nesting is spelled out with braces; the
     * binding rule is still exercised by the inner if/else. */
    {
        int t = 1, seen = 0;
        if (t) {
            if (!t)
                seen = 1;
            else
                seen = 2;
        }
        CHECK(seen == 2);
    }

    /* while, do-while (body runs at least once), for with all its parts. */
    {
        int k = 0, sum = 0;
        while (k < 5) { sum += k; ++k; }
        CHECK(sum == 10 && k == 5);

        k = 100;
        do { --k; } while (k > 5);
        CHECK(k == 5);

        sum = 0;
        k = 0;
        do { sum += 1; } while (0);       /* executes exactly once */
        CHECK(sum == 1 && k == 0);

        for (i = 0, j = 10; i < j; i++, j--) ;   /* comma in init/update */
        CHECK(i == 5 && j == 5);

        i = 0;
        for (;;) {                        /* infinite for with break */
            if (++i == 4) break;
        }
        CHECK(i == 4);

        i = 0;
        while (1) { if (i++ == 2) break; }
        CHECK(i == 3);

        i = 0;
        do { ++i; } while (1 == 0);
        CHECK(i == 1);

        /* for with a declaration whose scope is the loop. */
        int declared_inside = 0;
        for (int k2 = 0; k2 < 3; ++k2) declared_inside += k2;
        CHECK(declared_inside == 3);
    }

    /* continue in each loop form. */
    {
        int total = 0;
        for (i = 0; i < 10; ++i) {
            if (i % 2 != 0) continue;
            total += i;
        }
        CHECK(total == 20);

        i = 0;
        total = 0;
        while (i < 10) {
            ++i;
            if (i % 2 != 0) continue;
            total += i;
        }
        CHECK(total == 30);

        i = 0;
        total = 0;
        do {
            ++i;
            if (i % 2 != 0) continue;
            total += i;
        } while (i < 10);            /* continue jumps to the condition */
        CHECK(total == 30);
    }

    /* switch: fallthrough, default in the middle, break, nested switch,
     * and continue inside a switch inside a loop. */
    {
        int hits = 0;
        for (i = 0; i < 8; ++i) {
            switch (i) {
            case 0:
            case 1:
                hits += 1;
                break;
            case 2:
                hits += 10;
                /* fall through */
            case 3:
                hits += 100;
                break;
            default:
                hits += 1000;
                break;
            case 4:
                switch (i) {                 /* nested switch */
                case 4: continue;            /* continue: applies to for */
                default: break;
                }
                /* fall through */
            case 5:
                hits += 1;
                break;
            }
        }
        CHECK(hits == 1 + 1 + 110 + 100 + 1 + 1000 * 2);
    }

    /* goto: forward, backward, out of nested loops, and a label whose name
     * also exists as a variable (labels live in their own namespace). */
    {
        int counter = 0;
        int label = 0;
        goto forward;
    backward_target:
        ++counter;
        if (counter < 3) goto backward_target;
        goto done;

    forward:
        counter = 10;
        {
            for (i = 0; i < 3; ++i) {
                for (j = 0; j < 3; ++j) {
                    if (i == 1 && j == 1) goto out_of_loops;
                }
            }
        }
    out_of_loops:
        CHECK(counter == 10);
        CHECK(i == 1 && j == 1);
        goto after_backward;

    done:
        CHECK(counter == 3);
        label = 1;              /* the label `label` above is unrelated */
        (void)label;
    after_backward:
        ;
    }

    /* Empty statements and empty compound statements. */
    if (n == 6) ; else n = 0;
    while (0) ;
    for (i = 0; i < 1; ++i) { }
    CHECK(n == 6);

    return g_fail - failures;
}

/* ==========================================================================
 * 08 functions: prototypes, recursion, varargs, inline, VLA and array params
 * ========================================================================== */

static int c99_fact(int n)                       /* recursion */
{
    return n <= 1 ? 1 : n * c99_fact(n - 1);
}

static int c99_fib(int n)                        /* two recursive calls */
{
    return n < 2 ? n : c99_fib(n - 1) + c99_fib(n - 2);
}

static int c99_is_even(unsigned n);              /* mutual recursion */
static int c99_is_odd(unsigned n)
{
    return n == 0 ? 0 : c99_is_even(n - 1);
}
static int c99_is_even(unsigned n)
{
    return n == 0 ? 1 : c99_is_odd(n - 1);
}

/* Variadic: va_list, va_start, va_arg, va_copy (C99), va_end. */
static long long c99_varargs_longlong(int count, ...);

static int c99_sum_varargs(int count, ...)
{
    va_list ap, snapshot;
    int total = 0;

    va_start(ap, count);
    va_copy(snapshot, ap);
    for (int i = 0; i < count; ++i) {
        total += va_arg(ap, int);
    }
    va_end(ap);
    for (int i = 0; i < count; ++i) {
        total += va_arg(snapshot, int);
    }
    va_end(snapshot);
    return total;
}

/* vsnprintf is a C99 addition; so is the restrict qualifier on pointers. */
static int c99_format_into(char *restrict buf, size_t n,
                           const char *restrict fmt, ...)
{
    va_list ap;
    int written;

    va_start(ap, fmt);
    written = vsnprintf(buf, n, fmt, ap);
    va_end(ap);
    return written;
}

/* Variable-length arrays as parameters, with the size passed in.  In a
 * prototype the size may also be written [*] to mean "a VLA of unknown size";
 * see the function pointer in sec_08_functions for that spelling. */
static int c99_vla_param_sum(int n, int values[n]);
static int c99_vla_param_sum(int n, int values[n])
{
    int total = 0;
    for (int i = 0; i < n; ++i) {
        total += values[i];
    }
    return total;
}
static int c99_vla_star_sum(int n, int values[n]);
static int c99_vla_star_sum(int n, int values[n])
{
    return c99_vla_param_sum(n, values);
}

/* A parameter declared [static N] promises at least N elements. */
static int c99_static_extent_param(const int values[static 4])
{
    return values[0] + values[1] + values[2] + values[3];
}

/* An array parameter is adjusted to a pointer type (C99 6.7.5.3p7), so a
 * sizeof inside such a function reports the size of a pointer, never the
 * caller's array.  The array spelling in a parameter list is exercised by
 * c99_static_extent_param ([static 4]) and the VLA parameters above. */
static size_t c99_pointer_sizeof(int *values)
{
    return sizeof values;
}

/* A function returning a pointer to an array (12-level declarator syntax). */
static int c99_three_row[3] = {7, 8, 9};
static int (*c99_get_three(void))[3]
{
    return &c99_three_row;
}

/* Returning a structure by value. */
static c99_pair_t c99_make_pair(int a, int b)
{
    c99_pair_t result;
    result.a = a;
    result.b = b;
    return result;
}

/* A function taking and returning a function pointer. */
static int c99_apply(int (*fn)(int, int), int a, int b)
{
    return fn(a, b);
}

/* A function whose last statement is not a return: reaching the end of a
 * non-void function is only well-defined if the caller ignores the value. */
static int c99_return_from_block(int n)
{
    if (n > 0) {
        {
            return n * 2;
        }
    }
    return 0;
}

/* static inline: internal linkage, inlinable, always emitted. */
static inline int c99_inline_local(int x)
{
    return x + 1;
}

/* C99 6.7.4: a definition that is `inline` without `extern` is an inline
 * definition and does NOT provide an external definition, so calling it would
 * need one elsewhere; `extern inline` does provide it.  Only the second is
 * called below. */
inline int c99_inline_only(void)
{
    return 41;
}
extern inline int c99_inline_and_extern(void)
{
    return 42;
}

static int sec_08_functions(void)
{
    int failures = g_fail;
    int calls[8] = {1, 2, 3, 4, 5, 6, 7, 8};
    int star_calls[3] = {10, 20, 30};
    int quad[4] = {1, 1, 1, 1};
    char buffer[64];
    c99_pair_t made;
    int (*row)[3];

    sec_begin("08 functions");

    CHECK(c99_fact(0) == 1 && c99_fact(5) == 120);
    CHECK(c99_fib(10) == 55);
    CHECK(c99_is_even(10) == 1 && c99_is_odd(10) == 0);
    CHECK(c99_is_even(7) == 0 && c99_is_odd(7) == 1);
    CHECK(c99_sum_varargs(4, 1, 2, 3, 4) == 20);          /* 2 * (1+2+3+4) */
    CHECK(c99_sum_varargs(1, 5) == 10);
    CHECK(c99_format_into(buffer, sizeof buffer, "%d-%s-%.2f", 7, "x", 0.5) == 8);
    CHECK(strcmp(buffer, "7-x-0.50") == 0);
    CHECK(c99_format_into(buffer, 4, "%s", "truncated") == 9); /* needs 9 */
    CHECK(strcmp(buffer, "tru") == 0);                    /* properly cut */
    buffer[0] = '\0';
    CHECK(c99_format_into(buffer, 0, "%d", 1) < 0 || buffer[0] == '\0');

    CHECK(c99_vla_param_sum(8, calls) == 36);
    CHECK(c99_vla_star_sum(3, star_calls) == 60);
    /* [*] is the spelling for a VLA parameter of unknown bound, allowed only in
     * a prototype (C99 6.7.5.2p4) -- here inside a function pointer type. */
    {
        int (*unbounded)(int, int[*]) = c99_vla_star_sum;
        CHECK(unbounded(3, star_calls) == 60);
    }
    CHECK(c99_static_extent_param(quad) == 4);
    CHECK(c99_pointer_sizeof(calls) == sizeof(int *));
    CHECK(sizeof calls == 8 * sizeof(int));
    row = c99_get_three();
    CHECK((*row)[0] == 7 && (*row)[2] == 9 && sizeof *row == 3 * sizeof(int));
    CHECK(row[0][0] == 7 && (*row)[2] == 9 && sizeof *row == 3 * sizeof(int));

    made = c99_make_pair(11, 22);
    CHECK(made.a == 11 && made.b == 22);
    CHECK(c99_apply(c99_add, 3, 4) == 7);
    CHECK(c99_apply(c99_mul, 3, 4) == 12);
    CHECK(c99_return_from_block(3) == 6 && c99_return_from_block(0) == 0);
    CHECK(c99_inline_local(1) == 2);
    CHECK(c99_inline_and_extern() == 42);

    /* A call through a pointer to the array-returning function type. */
    {
        int (*(*fp)(void))[3] = c99_get_three;
        CHECK((*fp())[1] == 8);
    }

    /* varargs: passing a struct-like mix through va_arg. */
    {
        /* Wide and long long arguments through varargs. */
        long long big = 1LL << 40;
        CHECK(c99_varargs_longlong(2, 1LL, big) == (1LL << 40) + 1);
    }

    return g_fail - failures;
}

static long long c99_varargs_longlong(int count, ...)
{
    va_list ap;
    long long total = 0;

    va_start(ap, count);
    for (int i = 0; i < count; ++i) {
        total += va_arg(ap, long long);
    }
    va_end(ap);
    return total;
}

/* ==========================================================================
 * 09 aggregates: struct, union, enum, flexible array members
 * ========================================================================== */

struct c99_node {                    /* self-referential structure */
    int value;
    struct c99_node *next;
};

struct c99_nested {                  /* struct inside struct inside struct */
    struct {
        int x;
        int y;
    } point;
    union {
        int as_int;
        char as_bytes[sizeof(int)];
    } pun;
    struct c99_node chain[2];
};

/* Flexible array member: the last member may be an array of unspecified size.
 * sizeof excludes it and such a struct may not be a member of another struct. */
struct c99_fam {
    size_t length;
    char data[];
};

/* Union with members of different size and alignment. */
union c99_mixed {
    char c;
    short s;
    int i;
    long long ll;
    double d;
    char bytes[8];
};

static int c99_pair_sum(c99_pair_t p);

static int sec_09_aggregates(void)
{
    int failures = g_fail;
    struct c99_nested nested = {
        {1, 2},
        {0},
        {{3, NULL}, {4, NULL}}
    };
    struct c99_nested copy;
    c99_pair_t pair = {5, 6};
    c99_pair_t pair_copy;
    union c99_mixed mixed;
    struct c99_fam *fam;
    struct c99_node a = {1, NULL};
    struct c99_node b = {2, &a};
    struct c99_node *walk;

    sec_begin("09 aggregates");

    CHECK(nested.point.x == 1 && nested.point.y == 2);
    CHECK(nested.chain[0].value == 3 && nested.chain[1].value == 4);
    CHECK(nested.chain[0].next == NULL && nested.chain[1].next == NULL);

    /* Structure assignment copies every member (including arrays). */
    copy = nested;
    copy.point.x = 99;
    copy.chain[1].value = 44;
    CHECK(nested.point.x == 1 && copy.point.x == 99);
    CHECK(nested.chain[1].value == 4 && copy.chain[1].value == 44);
    pair_copy = pair;
    CHECK(pair_copy.a == 5 && pair_copy.b == 6);

    /* Union: only the last stored member is valid, and all members share the
     * same address. */
    mixed.ll = 0;
    mixed.i = 0x01020304;
    CHECK((void *)&mixed.i == (void *)&mixed);
    CHECK((void *)&mixed.c == (void *)&mixed);
    CHECK(sizeof(union c99_mixed) == 8);
    CHECK(mixed.i == 0x01020304);
    CHECK(mixed.bytes[sizeof(int) - 1] == 1 || mixed.bytes[0] == 4);
    mixed.d = 1.0;                     /* re-using the same storage */
    CHECK(mixed.d == 1.0);
    mixed.c = 'z';
    CHECK(mixed.c == 'z');

    /* Linked structure through pointers. */
    walk = &b;
    CHECK(walk->value == 2 && walk->next->value == 1);
    CHECK(walk->next->next == NULL);
    a.next = &b;
    CHECK(b.next->next->value == 2);

    /* Flexible array member. */
    fam = malloc(sizeof *fam + 16);
    CHECK(fam != NULL);
    if (fam != NULL) {
        fam->length = 16;
        memcpy(fam->data, "0123456789abcdef", 16);
        CHECK(fam->length == 16);
        CHECK(fam->data[0] == '0' && fam->data[15] == 'f');
        CHECK(sizeof *fam == sizeof(size_t));    /* FAM is not counted */
        free(fam);
    }

    /* Structures as call arguments and return values. */
    {
        c99_pair_t from_call = c99_make_pair(8, 9);
        CHECK(from_call.a == 8 && from_call.b == 9);
        CHECK(c99_pair_sum(from_call) == 17);
    }

    /* arrays of structs, and pointers to struct members. */
    {
        c99_pair_t table[3] = {{1, 2}, {3, 4}, {5, 6}};
        c99_pair_t *entry = table;
        int *member = &table[1].b;
        CHECK(entry[2].a == 5 && (entry + 2)->b == 6);
        CHECK(*member == 4);
        member = &table[0].a;
        CHECK(*member == 1);
        CHECK(sizeof table == 3 * sizeof(c99_pair_t));
    }

    /* offsetof on nested members. */
    CHECK(offsetof(struct c99_nested, point.y) == sizeof(int));
    CHECK(offsetof(struct c99_nested, chain) > offsetof(struct c99_nested, point));
    CHECK(offsetof(struct c99_fam, data) == sizeof(size_t));
    CHECK(offsetof(struct c99_node, next) >= sizeof(int));

    return g_fail - failures;
}

static int c99_pair_sum(c99_pair_t p)
{
    return p.a + p.b;
}

/* ==========================================================================
 * 10 arrays, initializers, compound literals, variable-length arrays
 * ========================================================================== */

static int c99_2d[2][3] = {{1, 2, 3}, {4, 5, 6}};
static int c99_3d[2][2][2] = {{{1, 2}, {3, 4}}, {{5, 6}, {7, 8}}};
static int c99_flat[6] = {1, 2, 3, 4, 5, 6};

static int c99_row_sum(const int *row, size_t n)
{
    int total = 0;
    for (size_t i = 0; i < n; ++i) {
        total += row[i];
    }
    return total;
}

static int c99_vla_sum(int n, int values[n]);   /* defined below this section */

static int sec_10_arrays(void)
{
    int failures = g_fail;
    int deduced[] = {2, 3, 5, 7, 11};                 /* size from initializer */
    int partial[6] = {1, 2};                          /* rest zeroed */
    int designated[6] = {[4] = 40, [0] = 1, [2] = 20}; /* out of order */
    int flat_designated[] = {[0] = 1, [1] = 2, [2] = 3};
    char exact[3];
    memcpy(exact, "abc", 3);        /* C also allows char exact[3] = "abc";
                                     * GCC 16 warns about the truncating
                                     * initializer, so the same three bytes are
                                     * copied instead. */
    char terminated[4] = "abc";
    char deduced_string[] = "abc";
    const char *strings[3] = {"one", "two", "three"};
    enum { ROWS = 2, COLS = 3 };
    int from_enum[ROWS][COLS] = {{0}};
    const int not_a_constant_expression = 4;
    int vla[not_a_constant_expression];               /* VLA: const is not
                                                       * an integer constant
                                                       * expression in C99 */
    int *flat_view = &c99_2d[0][0];
    int (*row_ptr)[3] = c99_2d;

    sec_begin("10 arrays, initializers, compound literals, VLAs");

    CHECK(sizeof deduced == 5 * sizeof(int) && deduced[4] == 11);
    CHECK(sizeof partial == 6 * sizeof(int));
    CHECK(partial[0] == 1 && partial[1] == 2 && partial[2] == 0);
    CHECK(designated[0] == 1 && designated[2] == 20 && designated[4] == 40);
    CHECK(designated[1] == 0 && designated[3] == 0 && designated[5] == 0);
    CHECK(sizeof flat_designated == 3 * sizeof(int));
    CHECK(sizeof exact == 3 && exact[0] == 'a' && exact[2] == 'c');
    CHECK(sizeof terminated == 4 && terminated[3] == '\0');
    CHECK(sizeof deduced_string == 4 && deduced_string[3] == '\0');
    CHECK(strcmp(strings[2], "three") == 0 && sizeof strings == 3 * sizeof(char *));

    CHECK(sizeof c99_2d == 6 * sizeof(int));
    CHECK(sizeof c99_2d[0] == 3 * sizeof(int));
    CHECK(c99_2d[1][2] == 6 && *(*(c99_2d + 1) + 2) == 6);
    CHECK(c99_row_sum(c99_2d[1], 3) == 15);
    CHECK(flat_view[4] == 5 && flat_view[5] == 6);
    CHECK(row_ptr[1][0] == 4 && (*(row_ptr + 1))[1] == 5);
    CHECK(flat_view + 3 == c99_2d[1]);

    CHECK(sizeof c99_3d == 8 * sizeof(int));
    CHECK(c99_3d[1][0][1] == 6 && c99_3d[0][1][0] == 3);
    CHECK(sizeof c99_flat == 6 * sizeof(int) && c99_flat[5] == 6);

    CHECK(from_enum[0][0] == 0 && from_enum[1][2] == 0);
    CHECK(ROWS == 2 && COLS == 3);

#ifdef C99_BRACE_ELISION
    /* Brace elision: {1, 2, 3, 4} initialising an int[2][2].  Legal in C99,
     * but GCC and Clang both diagnose it (-Wmissing-braces), so it is off by
     * default. */
    {
        int nested_brackets[2][2] = {1, 2, 3, 4};
        CHECK(sizeof nested_brackets == 4 * sizeof(int));
        CHECK(nested_brackets[0][0] == 1 && nested_brackets[1][1] == 4);
    }
#endif

    /* VLA: the bound is evaluated at run time, sizeof is not a constant, and
     * a VLA may not be initialized. */
    CHECK(sizeof vla == 4 * sizeof(int));
    vla[0] = 10;
    vla[1] = 20;
    vla[2] = 30;
    vla[3] = 40;
    CHECK(c99_vla_sum(4, vla) == 100);
    {
        int rows = 2, cols = 3;
        int matrix[rows][cols];                       /* 2-D VLA */
        int total = 0;
        for (int i = 0; i < rows; ++i) {
            for (int j = 0; j < cols; ++j) {
                matrix[i][j] = i * 10 + j;
                total += matrix[i][j];
            }
        }
        CHECK(sizeof matrix == (size_t)(rows * cols) * sizeof(int));
        CHECK(total == 36);                  /* 0+1+2 + 10+11+12 */
        CHECK(matrix[1][2] == 12);
    }

    /* Compound literals (C99 6.5.2.5): unnamed objects with the lifetime of
     * the enclosing block. */
    {
        int *arr = (int[]){10, 20, 30};
        c99_pair_t *pr = &(c99_pair_t){3, 4};
        int sum = c99_row_sum((const int[]){1, 2, 3, 4}, 4);
        CHECK(arr[0] == 10 && arr[2] == 30);
        arr[1] = 21;                      /* compound literals are lvalues */
        CHECK(arr[1] == 21);
        CHECK(pr->a == 3 && pr->b == 4);
        pr->a = 5;
        CHECK(pr->a == 5);
        CHECK(sum == 10);
        CHECK(c99_pair_sum((c99_pair_t){1, 1}) == 2);
        CHECK(sizeof (int[]){1, 2, 3} == 3 * sizeof(int));
        CHECK(sizeof (c99_pair_t){1, 2} == sizeof(c99_pair_t));
    }

    /* Designated initializers for structures, including nested designators
     * and out-of-order members. */
    {
        struct c99_nested n = {.point = {.y = 2, .x = 1}, .chain[1] = {4, NULL}};
        c99_pair_t p = {.b = 2, .a = 1};
        struct c99_node nodes[3] = {[0] = {1, NULL}, [2] = {3, NULL}, [1] = {2, NULL}};
        CHECK(n.point.x == 1 && n.point.y == 2);
        CHECK(n.chain[1].value == 4 && n.chain[0].value == 0);
        CHECK(p.a == 1 && p.b == 2);
        CHECK(nodes[0].value == 1 && nodes[1].value == 2 && nodes[2].value == 3);
    }

    return g_fail - failures;
}

static int c99_vla_sum(int n, int values[n])
{
    int total = 0;
    for (int i = 0; i < n; ++i) {
        total += values[i];
    }
    return total;
}

/* ==========================================================================
 * 11 pointers
 * ========================================================================== */

static int c99_pointer_add(int a, int b) { return a + b; }
static int c99_pointer_mul(int a, int b) { return a * b; }
static int printf_like_noop(const char *unused, ...);

static int (*const c99_pointer_table[2])(int, int) = {c99_pointer_add, c99_pointer_mul};

struct c99_outer {
    int pad;
    c99_pair_t inner;
};

static int sec_11_pointers(void)
{
    int failures = g_fail;
    int values[5] = {0, 10, 20, 30, 40};
    int *p = values;
    int *q = values + 4;
    const int *pc = values;
    int *const cp = values;
    int **pp = &p;
    void *vp = values;
    char *bytes = (char *)values;
    struct c99_outer outer = {0, {7, 8}};
    c99_pair_t *inner_ptr = &outer.inner;
    int (*row)[5] = &values;
    int *ptrs[3] = {&values[0], &values[1], &values[2]};

    sec_begin("11 pointers");

    CHECK(p == values && *p == 0 && p[1] == 10 && *(p + 2) == 20);
    CHECK(q - p == 4 && p + 4 == q && q > p && p < q);
    CHECK(pc == values && *pc == 0);
    *cp = 1;
    CHECK(values[0] == 1);
    CHECK(*pp == p && **pp == 1);
    CHECK((int *)vp == values && ((int *)vp)[1] == 10);

    /* sizeof a pointer, and pointer arithmetic in bytes. */
    CHECK(sizeof p == sizeof(int *) && sizeof(void *) == sizeof(char *));
    CHECK(sizeof p == sizeof row);
    CHECK((void *)(bytes + sizeof(int)) == (void *)(values + 1));
    CHECK(bytes[0] == 1 && bytes[sizeof(int)] == 10);

    /* Null pointers: the null pointer constant, NULL, and (void *)0. */
    {
        int *null_one = 0;
        int *null_two = NULL;
        int *null_three = (void *)0;
        CHECK(null_one == NULL && null_two == NULL && null_three == NULL);
        CHECK(!null_one && !(p == NULL));
    }

    /* Pointer to array versus array of pointers. */
    CHECK((*row)[2] == 20 && sizeof *row == 5 * sizeof(int));
    CHECK(sizeof row == sizeof(int (*)[5]));
    CHECK(*ptrs[1] == 10 && *ptrs[2] == 20);
    CHECK(sizeof ptrs == 3 * sizeof(int *));
    CHECK(*values == values[0]);

    /* Function pointers: a const table, calls through the table, and a
     * pointer-to-function with a variadic type. */
    CHECK(c99_pointer_table[0](3, 4) == 7);
    CHECK(c99_pointer_table[1](3, 4) == 12);
    CHECK((*c99_pointer_table[0])(3, 4) == 7);
    {
        int (*chosen)(int, int) = c99_pointer_table[1];
        int (*variadic)(const char *, ...) = printf_like_noop;
        CHECK(chosen(5, 6) == 30);
        CHECK(variadic("...") == 0);
        CHECK(chosen == c99_pointer_table[1] && chosen != c99_pointer_table[0]);
    }

    /* Recovering the enclosing structure from a member pointer (the offsetof
     * idiom): the pointer arithmetic is done in bytes. */
    {
        struct c99_outer *recovered =
            (struct c99_outer *)(void *)((char *)inner_ptr -
                                         offsetof(struct c99_outer, inner));
        CHECK(recovered == &outer);
        CHECK(recovered->inner.a == 7 && recovered->inner.b == 8);
    }

    /* Pointer casts preserve values when round-tripped. */
    {
        void *as_void = p;
        int *back = (int *)as_void;
        char *as_char = (char *)(void *)p;
        CHECK(back == p && as_char == (char *)p);
        CHECK((void *)0 == (int *)0);
    }

    /* Pointer to pointer to pointer, and dereferencing each level. */
    {
        int **level2 = &p;
        int ***level3 = &level2;
        CHECK(***level3 == *p);        /* the int itself */
        CHECK(**level3 == p);          /* the int * */
        CHECK(*level3 == &p);          /* the int ** */
    }

    /* const-qualified pointee and pointer. */
    {
        const char *literal = "abc";
        const char *const both = "abc";
        CHECK(literal[0] == 'a' && both[1] == 'b');
    }

    return g_fail - failures;
}

/* A function with a variadic type, called through a function pointer. */
static int printf_like_noop(const char *unused, ...)
{
    return unused != NULL ? 0 : 1;
}

/* ==========================================================================
 * 12 characters, wide characters, multibyte conversion
 * ========================================================================== */

static int sec_12_characters(void)
{
    int failures = g_fail;
    const char *letters = "abcXYZ123 \t.,;";
    wchar_t wide_letters[] = L"abcXYZ123 \t.,;";

    sec_begin("12 characters and wide characters");

    /* <ctype.h>.  isblank is a C99 addition. */
    CHECK(isalpha('a') && isalpha('Z') && !isalpha('1'));
    CHECK(isdigit('7') && !isdigit('a'));
    CHECK(isalnum('a') && isalnum('7') && !isalnum(' '));
    CHECK(isspace(' ') && isspace('\t') && isspace('\n'));
    CHECK(ispunct('.') && ispunct(',') && !ispunct('a'));
    CHECK(isupper('A') && !isupper('a') && islower('a') && !islower('A'));
    CHECK(isxdigit('f') && isxdigit('F') && isxdigit('9') && !isxdigit('g'));
    CHECK(iscntrl('\t') && !iscntrl('a'));
    CHECK(isgraph('!') && !isgraph(' '));
    CHECK(isprint(' ') && isprint('!') && !isprint('\t'));
    CHECK(isblank(' ') && isblank('\t') && !isblank('\n'));
    CHECK(tolower('A') == 'a' && toupper('a') == 'A');
    CHECK(tolower('1') == '1' && toupper('1') == '1');
    CHECK(isalpha(EOF) == 0 && isdigit(EOF) == 0);   /* EOF is allowed here */
    CHECK(EOF == -1 && tolower(EOF) == EOF && toupper(EOF) == EOF);
    CHECK(wcslen(wide_letters) == 14);               /* the same text, wide */

    /* Every ctype predicate accepts the whole range of unsigned char. */
    {
        int flags = 0;
        for (int c = 0; c < 256; ++c) {
            flags += isalpha(c) != 0;
        }
        CHECK(flags == 52);            /* 26 lower + 26 upper in the C locale */
    }

    /* Walking a string with ctype predicates and pointers. */
    {
        const char *scan = letters;
        int alnum_count = 0, punct_count = 0;
        while (*scan != '\0') {
            if (isalnum((unsigned char)*scan)) {
                ++alnum_count;
            } else if (ispunct((unsigned char)*scan)) {
                ++punct_count;
            }
            ++scan;
        }
        CHECK(alnum_count == 9 && punct_count == 3);
    }

    /* <wctype.h>: wide classification and mapping. */
    CHECK(sizeof(wchar_t) >= 2 && WEOF == (wint_t)-1);
    CHECK(iswalpha(L'a') && iswalpha(L'Z') && !iswalpha(L'1'));
    CHECK(iswdigit(L'7') && iswspace(L' ') && iswspace(L'\t'));
    CHECK(iswupper(L'A') && iswlower(L'a'));
    CHECK(iswblank(L' ') && iswblank(L'\t') && !iswblank(L'\n'));
    CHECK(iswpunct(L'.') && iswcntrl(L'\t') && iswprint(L' ') && iswgraph(L'!'));
    CHECK(iswxdigit(L'f') && iswxdigit(L'9'));
    CHECK(towlower(L'A') == L'a' && towupper(L'a') == L'A');
    CHECK(towlower(L'a') == L'a' && towupper(L'A') == L'A');

    /* Locale-independent but classification-driven: iswctype and towctrans.
     * wctype() and wctrans() return objects usable with iswctype/towctrans. */
    {
        wctype_t alpha_class = wctype("alpha");
        wctype_t digit_class = wctype("digit");
        wctrans_t lower_map = wctrans("tolower");
        wctrans_t upper_map = wctrans("toupper");
        CHECK(alpha_class != (wctype_t)0);
        CHECK(digit_class != (wctype_t)0);
        CHECK(iswctype(L'a', alpha_class) != 0);
        CHECK(iswctype(L'1', digit_class) != 0);
        CHECK(iswctype(L'1', alpha_class) == 0);
        if (lower_map != (wctrans_t)0) {
            CHECK(towctrans(L'A', lower_map) == L'a');
        }
        if (upper_map != (wctrans_t)0) {
            CHECK(towctrans(L'a', upper_map) == L'A');
        }
        CHECK(towctrans(L'1', lower_map) == L'1');
    }

    /* Wide character constants and wide string literals. */
    {
        wchar_t wc = L'A';
        wchar_t wbuf[] = L"abc";
        const wchar_t *wptr = L"xyz";
        CHECK(wc == 65 && sizeof(wc) == sizeof(wchar_t));
        CHECK(sizeof wbuf == 4 * sizeof(wchar_t));
        CHECK(wbuf[0] == L'a' && wbuf[3] == L'\0');
        CHECK(wptr[2] == L'z' && *wptr == L'x');
        CHECK(L'\n' == (wchar_t)10 && L'\t' == (wchar_t)9);
    }

    /* Wide string functions. */
    CHECK(wcslen(L"hello") == 5 && wcslen(L"") == 0);
    CHECK(wcscmp(L"abc", L"abc") == 0);
    CHECK(wcscmp(L"abc", L"abd") < 0 && wcscmp(L"abd", L"abc") > 0);
    CHECK(wcschr(L"abc", L'b') != NULL && *wcschr(L"abc", L'b') == L'b');
    CHECK(wcsstr(L"hello world", L"world") != NULL);
    CHECK(wcsstr(L"hello", L"xyz") == NULL);
    {
        wchar_t dest[16];
        wcscpy(dest, L"copy");
        CHECK(wcscmp(dest, L"copy") == 0);
        wcscat(dest, L"2");
        CHECK(wcscmp(dest, L"copy2") == 0);
        CHECK(swprintf(dest, 16, L"%ls-%d", L"n", 5) == 3);
        CHECK(wcscmp(dest, L"n-5") == 0);
    }

    /* Wide numeric conversions (all C99 additions to <wchar.h>). */
    CHECK(wcstod(L"2.5", NULL) == 2.5);
    CHECK(wcstoll(L"123", NULL, 10) == 123LL);
    CHECK(wcstoull(L"123", NULL, 10) == 123ULL);
    CHECK(wcstoimax(L"-9", NULL, 10) == -9);
    {
        wchar_t *end = NULL;
        long value = wcstol(L"42xyz", &end, 10);
        CHECK(value == 42 && end != NULL && *end == L'x');
    }

    /* Multibyte/wide conversion state machine (C99 7.24.6). */
    {
        mbstate_t state;
        wchar_t converted = 0;
        char narrow[MB_LEN_MAX];
        size_t result;

        memset(&state, 0, sizeof state);
        CHECK(mbsinit(&state) != 0);
        result = mbrtowc(&converted, "A", 1, &state);
        CHECK(result == 1 && converted == L'A');
        result = mbrtowc(NULL, "", 1, &state);
        CHECK(result == 0);                 /* no incomplete character */
        result = wcrtomb(narrow, L'Z', &state);
        CHECK(result == 1 && narrow[0] == 'Z');
        CHECK(btowc('A') == L'A');
        CHECK(wctob(L'A') == 'A');
        CHECK(wctob(WEOF) == EOF);
        CHECK(MB_CUR_MAX >= 1 && MB_LEN_MAX >= MB_CUR_MAX);
    }

    /* Multibyte string conversions. */
    {
        wchar_t wide_result[16];
        char narrow_result[16];
        size_t count = mbstowcs(wide_result, "abc", 16);
        CHECK(count == 3 && wcscmp(wide_result, L"abc") == 0);
        count = wcstombs(narrow_result, L"xyz", 16);
        CHECK(count == 3 && strcmp(narrow_result, "xyz") == 0);
        CHECK(mbstowcs(NULL, "", 0) == 0);
    }

    /* A wide stream: fwide fixes the orientation of a fresh FILE, after which
     * only wide-character I/O may be used on it.  This is done on a temporary
     * file because mixing byte and wide I/O on stdout is undefined. */
    {
        FILE *wf = tmpfile();
        if (wf != NULL) {
            wchar_t readback[32];
            CHECK(fwide(wf, 0) == 0);            /* no orientation yet */
            CHECK(fwide(wf, 1) > 0);             /* make it wide */
            CHECK(fwide(wf, 0) > 0);             /* and report it */
            CHECK(fwprintf(wf, L"%ls-%d", L"wide", 7) == 6);
            rewind(wf);
            CHECK(fgetws(readback, 32, wf) == readback);
            CHECK(wcscmp(readback, L"wide-7") == 0);
            fclose(wf);
        }
    }

    return g_fail - failures;
}

/* ==========================================================================
 * 13 strings and byte arrays
 *
 * <string.h> gained no new functions in C99; the interesting part is the
 * exact behaviour of the C89 functions (truncation, overlap, embedded NULs)
 * and that the prototypes now carry restrict qualifiers.
 * ========================================================================== */

static int sec_13_strings(void)
{
    int failures = g_fail;
    char buffer[64];
    char copy[64];
    const char *source = "abcdefghij";

    sec_begin("13 strings and byte arrays");

    CHECK(strlen("") == 0 && strlen("abc") == 3 && strlen(source) == 10);
    CHECK(strlen(source) == sizeof "abcdefghij" - 1);

    strcpy(copy, "hello");
    CHECK(strcmp(copy, "hello") == 0 && copy[5] == '\0');
    strcat(copy, " world");
    CHECK(strcmp(copy, "hello world") == 0);
    {
        /* strncat appends at most n characters and always terminates.  The
         * count is a volatile load so that -Wstringop-truncation does not fire
         * at -O2 about the deliberate truncation. */
        volatile size_t append_bound = 2;
        CHECK(strncat(copy, "!!!", append_bound) == copy);
        CHECK(strcmp(copy, "hello world!!") == 0);
    }

    /* strncpy pads with NULs but does not terminate a truncated copy.  The
     * bound is a volatile load so that -Wstringop-truncation stays quiet
     * about the deliberate truncation at every optimization level. */
    {
        volatile size_t bound = 4;
        memset(buffer, '#', sizeof buffer);
        strncpy(buffer, source, bound);
        buffer[bound] = '\0';               /* the caller's job */
        CHECK(strcmp(buffer, "abcd") == 0);
        CHECK(buffer[bound - 1] == 'd' && buffer[bound] == '\0');
        memset(buffer, 0, sizeof buffer);
        strncpy(buffer, "ab", 8);
        CHECK(buffer[0] == 'a' && buffer[1] == 'b' && buffer[2] == '\0');
    }

    CHECK(strcmp("abc", "abc") == 0);
    CHECK(strcmp("abc", "abd") < 0 && strcmp("abd", "abc") > 0);
    CHECK(strncmp("abcde", "abcXX", 3) == 0);
    CHECK(strncmp("abc", "abd", 3) < 0);
    CHECK(strncmp("abc", "abd", 2) == 0);

    CHECK(strchr("hello", 'l') != NULL && *(strchr("hello", 'l')) == 'l');
    CHECK(strchr("hello", 'z') == NULL);
    CHECK(strrchr("hello", 'l') == strchr("hello", 'l') + 1);
    CHECK(strstr("hello world", "world") != NULL);
    CHECK(strstr("hello", "xyz") == NULL && strstr("", "") != NULL);
    CHECK(strspn("abc123", "abc") == 3);
    CHECK(strcspn("abc123", "123") == 3);
    CHECK(strpbrk("abc123", "21") == strchr("abc123", '1'));
    CHECK(strpbrk("abc", "xyz") == NULL);

    /* strtok: the first call takes the string, later calls take NULL. */
    {
        char text[] = "one,two,,three";
        const char *token = strtok(text, ",");
        int tokens = 0;
        while (token != NULL) {
            ++tokens;
            token = strtok(NULL, ",");
        }
        CHECK(tokens == 3);      /* a run of delimiters counts as one */
    }

    /* strcoll and strxfrm: in the C locale strcoll matches strcmp, and
     * strxfrm returns the length the transformed string needs. */
    {
        char transformed[32];
        size_t needed = strxfrm(transformed, "abc", sizeof transformed);
        CHECK(needed == 3 && strcmp(transformed, "abc") == 0);
        CHECK(strcoll("abc", "abc") == 0);
        CHECK((strcoll("abc", "abd") < 0) == (strcmp("abc", "abd") < 0));
    }

    /* strerror over a couple of error numbers. */
    CHECK(strerror(0) != NULL && strlen(strerror(0)) > 0);
    CHECK(strerror(EDOM) != NULL && strerror(ERANGE) != NULL);
    CHECK(strcmp(strerror(EDOM), strerror(ERANGE)) != 0);

    /* Memory functions: memcpy, memmove (overlapping), memset, memcmp,
     * memchr -- all with explicit byte counts. */
    {
        char bytes[16];
        char overlapping[16] = "0123456789";
        memset(bytes, 0x5A, sizeof bytes);
        CHECK(bytes[0] == 0x5A && bytes[15] == 0x5A);
        memcpy(bytes, "ab\0cd", 5);
        CHECK(bytes[0] == 'a' && bytes[1] == 'b' && bytes[2] == '\0');
        CHECK(bytes[4] == 'd' && bytes[5] == 0x5A);
        CHECK(memchr(bytes, '\0', 5) == &bytes[2]);
        CHECK(memcmp("abc", "abc", 3) == 0);
        CHECK(memcmp("abc", "abd", 3) < 0);
        CHECK(memcmp("abd", "abc", 3) > 0);
        CHECK(memcmp("abc", "abcdef", 3) == 0);
        memmove(overlapping + 2, overlapping, 8);      /* overlapping copy */
        CHECK(memcmp(overlapping, "0101234567", 10) == 0);
        memmove(overlapping, overlapping + 2, 8);
        CHECK(memcmp(overlapping, "01234567", 8) == 0);
    }

    /* Byte arrays holding binary data, including embedded NUL bytes. */
    {
        unsigned char binary[8] = {0x00, 0x7F, 0x80, 0xFF, 'A', 0, 'B', 'C'};
        unsigned char other[8];
        memcpy(other, binary, sizeof binary);
        CHECK(memcmp(other, binary, sizeof binary) == 0);
        CHECK(binary[0] == 0 && binary[3] == 0xFF && binary[4] == 'A');
        CHECK(binary[5] == 0 && binary[7] == 'C');
    }

    /* String literals are not modifiable, so writable copies come from
     * arrays; adjacent literals concatenate into one. */
    {
        char writable[] = "change" " me";
        CHECK(strcmp(writable, "change me") == 0);
        writable[0] = 'C';
        CHECK(strcmp(writable, "Change me") == 0);
        CHECK(sizeof "a" "b" == 3);
    }

    /* Array of pointers to string literals, and a lookup loop. */
    {
        const char *const names[] = {"alpha", "beta", "gamma", NULL};
        int found = -1;
        for (int i = 0; names[i] != NULL; ++i) {
            if (strcmp(names[i], "beta") == 0) {
                found = i;
            }
        }
        CHECK(found == 1 && names[3] == NULL);
    }

    return g_fail - failures;
}

/* ==========================================================================
 * 14 numerics: floating-point classification, C99 math, tgmath, complex, fenv
 * ========================================================================== */

static double c99_nearly(double a, double b)
{
    double diff = fabs(a - b);
    double scale = fabs(a) > fabs(b) ? fabs(a) : fabs(b);
    return diff <= 1e-12 * (scale > 1.0 ? scale : 1.0);
}

static long double c99_nearlyl(long double a, long double b)
{
    long double diff = fabsl(a - b);
    long double scale = fabsl(a) > fabsl(b) ? fabsl(a) : fabsl(b);
    return diff <= 1e-18L * (scale > 1.0L ? scale : 1.0L);
}

static int gcd_like_noop(int a, int b);

static int sec_14_numerics(void)
{
    int failures = g_fail;
    volatile double zero = 0.0;
    volatile double one = 1.0;
    volatile double negative = -1.0;
    double inf = one / zero;                     /* volatile: not folded */
    double neg_inf = negative / zero;
    double not_a_number = inf - inf;
    double d = 2.5;
    float f = 2.5f;
    double integral_part = 0.0;
    int exponent = 0;
    int quo = 0;
    double fraction = modf(3.75, &integral_part);
    double significand = frexp(8.0, &exponent);
    double remainder_result = remquo(7.0, 3.0, &quo);

    sec_begin("14 numerics");

    /* Classification macros are C99 additions. */
    CHECK(isnan(not_a_number) != 0 && isnan(d) == 0);
    CHECK(isinf(inf) != 0 && isinf(neg_inf) != 0 && isinf(d) == 0);
    CHECK(isfinite(d) != 0 && isfinite(inf) == 0 && isfinite(not_a_number) == 0);
    CHECK(isnormal(1.0) != 0 && isnormal(0.0) == 0);
    CHECK(signbit(-1.0) != 0 && signbit(1.0) == 0);
    CHECK(fpclassify(1.0) == FP_NORMAL);
    CHECK(fpclassify(0.0) == FP_ZERO);
    CHECK(fpclassify(inf) == FP_INFINITE);
    CHECK(fpclassify(not_a_number) == FP_NAN);
    CHECK(fpclassify(DBL_MIN / 4.0) == FP_SUBNORMAL ||
          fpclassify(DBL_MIN / 4.0) == FP_ZERO);
    CHECK(isinf(HUGE_VAL) != 0 && isinf(HUGE_VALF) != 0 && isinf(HUGE_VALL) != 0);
    CHECK(isnan(NAN) != 0 && isinf(INFINITY) != 0);
    CHECK(inf > DBL_MAX && neg_inf < -DBL_MAX);

    /* The math_errhandling macro and its bits. */
    CHECK((math_errhandling & (MATH_ERRNO | MATH_ERREXCEPT)) != 0);

    /* C99 additions to <math.h>: rounding, roots, logs, scaling. */
    CHECK(c99_nearly(cbrt(27.0), 3.0));
    CHECK(c99_nearly(hypot(3.0, 4.0), 5.0));
    CHECK(c99_nearly(exp2(3.0), 8.0));
    CHECK(c99_nearly(log2(8.0), 3.0));
    CHECK(expm1(0.0) == 0.0 && log1p(0.0) == 0.0);
    CHECK(round(2.5) == 3.0 && round(-2.5) == -3.0);
    CHECK(trunc(2.7) == 2.0 && trunc(-2.7) == -2.0);
    CHECK(c99_nearly(roundf(1.5f), 2.0f));
    CHECK(lround(2.5) == 3L && llround(-2.5) == -3LL);
    CHECK(lroundf(0.4f) == 0L && llroundl(0.6L) == 1LL);
    CHECK(c99_nearly(rint(2.4), 2.0) && c99_nearly(nearbyint(2.4), 2.0));
    CHECK(lrint(2.4) == 2L);
    CHECK(c99_nearly(fdim(5.0, 3.0), 2.0) && c99_nearly(fdim(1.0, 3.0), 0.0));
    CHECK(fmax(3.0, 5.0) == 5.0 && fmin(3.0, 5.0) == 3.0);
    CHECK(c99_nearly(fma(2.0, 3.0, 4.0), 10.0));
    CHECK(nextafter(1.0, 2.0) > 1.0 && nextafter(1.0, 0.0) < 1.0);
    CHECK(nexttoward(1.0, 2.0L) > 1.0);
    CHECK(copysign(3.0, -1.0) == -3.0 && copysign(-3.0, 1.0) == 3.0);
    CHECK(c99_nearly(logb(8.0), 3.0) && ilogb(8.0) == 3);
    CHECK(scalbn(1.0, 10) == 1024.0 && scalbln(1.0, 10L) == 1024.0);
    CHECK(ldexp(0.5, 4) == 8.0);
    CHECK(significand == 0.5 && exponent == 4);
    CHECK(fraction == 0.75 && integral_part == 3.0);
    CHECK(fmod(7.0, 3.0) == 1.0 && remainder(7.0, 3.0) == 1.0);
    CHECK(remainder_result == 1.0 && quo == 2);
    CHECK(gcd_like_noop(12, 18) == 6);           /* exercises remainders */
    CHECK(c99_nearly(erf(0.0), 0.0) && c99_nearly(erfc(0.0), 1.0));
    CHECK(tgamma(5.0) == 24.0 && lgamma(1.0) == 0.0);
    CHECK(c99_nearly(tanh(0.0), 0.0) && c99_nearly(asinh(0.0), 0.0));
    CHECK(c99_nearly(atan2(1.0, 1.0), 0.7853981633974483));
    CHECK(c99_nearly(pow(2.0, 10.0), 1024.0) && c99_nearly(sqrt(2.0) * sqrt(2.0), 2.0));
    CHECK(fabs(-1.5) == 1.5 && fabsf(-1.5f) == 1.5f && fabsl(-1.5L) == 1.5L);
    CHECK(floor(-1.5) == -2.0 && ceil(-1.5) == -1.0);
    CHECK(floorf(-1.5f) == -2.0f && floorl(-1.5L) == -2.0L);
    CHECK(c99_nearly(powl(2.0L, 8.0L), 256.0L) && c99_nearly(fmodl(7.0L, 3.0L), 1.0L));
    CHECK(c99_nearly(sqrtf(9.0f), 3.0f) && c99_nearly(sqrtl(9.0L), 3.0L));
    CHECK(c99_nearly(cbrtl(27.0L), 3.0L) && c99_nearly(hypotl(3.0L, 4.0L), 5.0L));
    CHECK(c99_nearly(expm1l(0.0L), 0.0L) && c99_nearly(log1pl(0.0L), 0.0L));
    CHECK(c99_nearly(log2l(8.0L), 3.0L) && c99_nearly(exp2l(3.0L), 8.0L));
    CHECK(roundl(2.5L) == 3.0L && truncl(-2.7L) == -2.0L);
    CHECK(c99_nearly(nextafterl(1.0L, 2.0L), 1.0L + LDBL_EPSILON));
    CHECK(copysignl(3.0L, -1.0L) == -3.0L && fmaxl(1.0L, 2.0L) == 2.0L);
    CHECK(c99_nearly(fmal(2.0L, 3.0L, 4.0L), 10.0L) && fdiml(5.0L, 3.0L) == 2.0L);
    CHECK(c99_nearly(lgammal(1.0L), 0.0L) && c99_nearly(tgammal(5.0L), 24.0L));
    CHECK(c99_nearly(erfl(0.0L), 0.0L) && c99_nearly(erfcl(0.0L), 1.0L));

    /* NaN conversion functions (C99). */
    CHECK(isnan(nan("")) != 0 && isnan(nanf("")) != 0 && isnan(nanl("")) != 0);
    CHECK(isnan(sqrt(negative)) != 0);            /* sqrt of a negative */

    /* <tgmath.h>: one name, dispatched on the argument type. */
    CHECK(c99_nearly(sqrt(4.0f), 2.0) && sizeof(sqrt(4.0f)) == sizeof(float));
    CHECK(sizeof(sqrt(4.0)) == sizeof(double));
    CHECK(sizeof(sqrt(4.0L)) == sizeof(long double));
    CHECK(c99_nearly(fabs(-2.0f), 2.0) && sizeof(fabs(-2.0f)) == sizeof(float));
    CHECK(c99_nearly(pow(f, 2.0f), 6.25) && sizeof(pow(f, 2.0f)) == sizeof(float));
    CHECK(sizeof(sin(0.0f)) == sizeof(float));
    CHECK(sizeof(exp((long double)0.0)) == sizeof(long double));
    CHECK(sizeof(fmod(1.0f, 1.0f)) == sizeof(float));
    CHECK(c99_nearly(fmod(7.0, 3.0), 1.0));

    /* <complex.h>: the _Complex types, the I macro, and the complex library.
     * A bare _Complex means double _Complex. */
    {
        double complex z = 3.0 + 4.0 * I;
        double complex w = 1.0 - 2.0 * I;
        double _Complex bare = 1.0 + 1.0 * I;
        float complex fz = 1.0f + 1.0f * _Complex_I;
        long double complex lz = 2.0L + 0.0L * I;
        double complex product = z * w;          /* (3+4i)(1-2i) = 11-2i */
        double complex sum = z + w;
        double complex difference = z - w;

        CHECK(sizeof z == 2 * sizeof(double));
        CHECK(sizeof(bare) == sizeof(double complex));
        CHECK(creal(z) == 3.0 && cimag(z) == 4.0);
        CHECK(creal(sum) == 4.0 && cimag(sum) == 2.0);
        CHECK(creal(difference) == 2.0 && cimag(difference) == 6.0);
        CHECK(creal(product) == 11.0 && cimag(product) == -2.0);
        CHECK(z == 3.0 + 4.0 * I && z != w);
        CHECK(c99_nearly(cabs(z), 5.0));
        CHECK(c99_nearly(carg(bare), 0.7853981633974483));
        CHECK(creal(conj(z)) == 3.0 && cimag(conj(z)) == -4.0);
        CHECK(c99_nearly(creal(cexp(0.0)), 1.0) && c99_nearly(cimag(cexp(0.0)), 0.0));
        CHECK(c99_nearly(creal(clog(1.0)), 0.0) && c99_nearly(cimag(clog(1.0)), 0.0));
        CHECK(c99_nearly(creal(csqrt(4.0)), 2.0) && c99_nearly(cimag(csqrt(4.0)), 0.0));
        CHECK(c99_nearly(creal(cpow(2.0, 3.0)), 8.0));
        CHECK(c99_nearly(creal(cproj(z)), 3.0) && c99_nearly(cimag(cproj(z)), 4.0));
        CHECK(c99_nearly(creal(csin(0.0)), 0.0) && c99_nearly(creal(ccos(0.0)), 1.0));
        CHECK(c99_nearly(cimag(ctan(0.0)), 0.0));
        CHECK(c99_nearly(creal(csinh(0.0)), 0.0) && c99_nearly(creal(ccosh(0.0)), 1.0));
        CHECK(c99_nearly(creal(catanh(0.0)), 0.0) && c99_nearly(creal(casinh(0.0)), 0.0));
        CHECK(c99_nearly(creal(cacosh(1.0)), 0.0) && c99_nearly(creal(casin(0.0)), 0.0));
        CHECK(c99_nearly(creal(cacos(1.0)), 0.0) && c99_nearly(creal(catan(0.0)), 0.0));
        CHECK(crealf(fz) == 1.0f && cimagf(fz) == 1.0f);
        CHECK(c99_nearly(cabsl(lz), 2.0) && creall(lz) == 2.0L && cimagl(lz) == 0.0L);
        CHECK(c99_nearly(creal(csqrtf(4.0f)), 2.0) && c99_nearly(creal(csqrtl(4.0L)), 2.0));
        CHECK(c99_nearly(creal(csinf(0.0f)), 0.0) && c99_nearly(creal(cpowl(2.0L, 3.0L)), 8.0));
        CHECK(c99_nearly(cabs(conj(z)), 5.0));
        CHECK(c99_nearly(creal(z / (1.0 + 0.0 * I)), 3.0));

        /* Complex values through tgmath dispatch. */
        CHECK(c99_nearly(creal(sqrt(-1.0 + 0.0 * I)), 0.0));
        CHECK(c99_nearly(fabs(creal(z)), 3.0));
    }

    /* <fenv.h>: the floating-point environment. */
    {
        fenv_t saved;
        fexcept_t flags;
        volatile double tiny = 1e-300;

        CHECK(fegetenv(&saved) == 0);
        CHECK(feclearexcept(FE_ALL_EXCEPT) == 0);
        CHECK(fetestexcept(FE_ALL_EXCEPT) == 0);
        CHECK(feraiseexcept(FE_INEXACT) == 0);
        CHECK((fetestexcept(FE_ALL_EXCEPT) & FE_INEXACT) != 0);
        CHECK(feclearexcept(FE_INEXACT) == 0);
        CHECK(fetestexcept(FE_INEXACT) == 0);

        CHECK(fegetexceptflag(&flags, FE_ALL_EXCEPT) == 0);
        CHECK(fesetexceptflag(&flags, FE_ALL_EXCEPT) == 0);
        CHECK(fetestexcept(FE_ALL_EXCEPT) == 0);

        /* Rounding modes: FE_TONEAREST must work; the others may be
         * unsupported, in which case fesetround reports failure. */
        {
            int original = fegetround();
            CHECK(original == FE_TONEAREST || original == FE_DOWNWARD ||
                  original == FE_UPWARD || original == FE_TOWARDZERO);
            if (fesetround(FE_UPWARD) == 0) {
                CHECK(fegetround() == FE_UPWARD);
            }
            if (fesetround(FE_TOWARDZERO) == 0) {
                CHECK(fegetround() == FE_TOWARDZERO);
            }
            fesetround(original);
            CHECK(fegetround() == original);
        }

        CHECK(feholdexcept(&saved) == 0);
        CHECK(feraiseexcept(FE_DIVBYZERO) == 0);
        /* feupdateenv restores the saved environment but re-raises whatever
         * exception flags were set when it was called (C99 7.6.4.4). */
        CHECK(feupdateenv(&saved) == 0);
        CHECK((fetestexcept(FE_ALL_EXCEPT) & FE_DIVBYZERO) != 0);
        CHECK(fesetenv(&saved) == 0);
        CHECK(fetestexcept(FE_ALL_EXCEPT) == 0);

        /* An operation that loses precision sets FE_INEXACT (visible with
         * default compiler settings; -ffast-math would break this). */
        feclearexcept(FE_ALL_EXCEPT);
        d = tiny * tiny + 1.0;
        CHECK((fetestexcept(FE_ALL_EXCEPT) & FE_INEXACT) != 0 || d == 1.0);
        feclearexcept(FE_ALL_EXCEPT);
    }

    return g_fail - failures;
}

/* Integer helper used above: the Euclid loop is built from % and /. */
static int gcd_like_noop(int a, int b)
{
    while (b != 0) {
        int t = a % b;
        a = b;
        b = t;
    }
    return a;
}

/* ==========================================================================
 * 15 stdio
 * ========================================================================== */

static int c99_scan_into(const char *source, const char *fmt, ...)
{
    va_list ap;
    int converted;

    va_start(ap, fmt);
    converted = vsscanf(source, fmt, ap);   /* vsscanf is a C99 addition */
    va_end(ap);
    return converted;
}

static int sec_15_stdio(void)
{
    int failures = g_fail;
    char formatted[128];
    char word[16];
    int consumed = 0;
    int int_a = 0, int_b = 0;
    unsigned int uint_a = 0;
    double double_value = 0.0;
    float float_value = 0.0f;
    double d = 3.14159;

    sec_begin("15 stdio and formatted I/O");

    /* Stream macros and objects. */
    CHECK(stdout != NULL && stderr != NULL && stdin != NULL);
    CHECK(EOF == -1);
    CHECK(BUFSIZ > 0 && FILENAME_MAX > 0 && FOPEN_MAX > 0 && TMP_MAX > 0);
    CHECK(SEEK_SET == 0 && SEEK_CUR == 1 && SEEK_END == 2);

    /* printf-family conversions, one specifier at a time so that each
     * expectation is exact. */
    CHECK(snprintf(formatted, sizeof formatted, "%d", -42) == 3);
    CHECK(strcmp(formatted, "-42") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%i", 42) == 2);
    CHECK(strcmp(formatted, "42") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%u", 42u) == 2);
    CHECK(strcmp(formatted, "42") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%o", 8u) == 2);
    CHECK(strcmp(formatted, "10") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%#o", 8u) == 3);
    CHECK(strcmp(formatted, "010") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%x", 255u) == 2);
    CHECK(strcmp(formatted, "ff") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%X", 255u) == 2);
    CHECK(strcmp(formatted, "FF") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%#x", 255u) == 4);
    CHECK(strcmp(formatted, "0xff") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%c", 'A') == 1);
    CHECK(strcmp(formatted, "A") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%s", "abc") == 3);
    CHECK(strcmp(formatted, "abc") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%.2s", "abc") == 2);
    CHECK(strcmp(formatted, "ab") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%5d", 42) == 5);
    CHECK(strcmp(formatted, "   42") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%-5d|", 42) == 6);
    CHECK(strcmp(formatted, "42   |") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%05d", 42) == 5);
    CHECK(strcmp(formatted, "00042") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%+d", 42) == 3);
    CHECK(strcmp(formatted, "+42") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "% d", 42) == 3);
    CHECK(strcmp(formatted, " 42") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%*d", 5, 42) == 5);
    CHECK(strcmp(formatted, "   42") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%.*f", 2, d) == 4);
    CHECK(strcmp(formatted, "3.14") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%.3f", d) == 5);
    CHECK(strcmp(formatted, "3.142") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%e", 1234.5) == 12);
    CHECK(strcmp(formatted, "1.234500e+03") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%g", 0.0001) == 6);
    CHECK(strcmp(formatted, "0.0001") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%.3g", 1234.5) == 8);
    CHECK(strcmp(formatted, "1.23e+03") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%hhd", (int)(signed char)-1) == 2);
    CHECK(strcmp(formatted, "-1") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%hd", (int)(short)-2) == 2);
    CHECK(strcmp(formatted, "-2") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%ld", 123456789L) == 9);
    CHECK(strcmp(formatted, "123456789") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%lld", -1234567890123LL) == 14);
    CHECK(strcmp(formatted, "-1234567890123") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%jd", (intmax_t)-5) == 2);
    CHECK(strcmp(formatted, "-5") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%zu", (size_t)7) == 1);
    CHECK(strcmp(formatted, "7") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%td", (ptrdiff_t)-3) == 2);
    CHECK(strcmp(formatted, "-3") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%Lf", 1.5L) == 8);
    CHECK(strcmp(formatted, "1.500000") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "100%%") == 4);
    CHECK(strcmp(formatted, "100%") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "abc%n", &consumed) == 3);
    CHECK(consumed == 3);
    CHECK(snprintf(formatted, sizeof formatted, "%a", 1.0) == 6);
    CHECK(strcmp(formatted, "0x1p+0") == 0);            /* C99 hex float */
    CHECK(snprintf(formatted, sizeof formatted, "%A", 2.0) == 6);
    CHECK(strcmp(formatted, "0X1P+1") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%p", (void *)&consumed) > 0);
    /* the %p text itself is implementation-defined */
    CHECK(snprintf(formatted, sizeof formatted, "%.0f", 2.5) == 1);
    CHECK(strcmp(formatted, "2") == 0);

    /* snprintf returns the length that would have been needed.  The bound is
     * a variable so that -Wformat-truncation stays quiet about the deliberate
     * truncation. */
    {
        volatile size_t bound = 4;
        CHECK(snprintf(formatted, bound, "%s", "truncated") == 9);
        CHECK(strcmp(formatted, "tru") == 0);
    }
    CHECK(snprintf(formatted, 0, "%d", 1) == 1);   /* nothing is stored */
    CHECK(sprintf(formatted, "%s-%d", "sprintf", 1) == 9);
    CHECK(strcmp(formatted, "sprintf-1") == 0);

    /* sscanf and vsscanf. */
    CHECK(sscanf("42 -7 word 3.5", "%d %d %15s", &int_a, &int_b, word) == 3);
    CHECK(int_a == 42 && int_b == -7 && strcmp(word, "word") == 0);
    CHECK(sscanf("3.5", "%lf", &double_value) == 1 && double_value == 3.5);
    CHECK(sscanf("0x1f", "%x", &uint_a) == 1 && uint_a == 0x1fu);
    CHECK(sscanf("077", "%o", &uint_a) == 1 && uint_a == 63u);
    CHECK(sscanf("abc123", "%3s%n", word, &consumed) == 1);
    CHECK(consumed == 3 && strcmp(word, "abc") == 0);
    CHECK(sscanf("9 8", "%*d %d", &int_b) == 1 && int_b == 8);
    CHECK(sscanf("z", "%d", &int_a) == 0);
    CHECK(sscanf("", "%d", &int_a) == EOF);
    {
        signed char narrow = 0;
        CHECK(sscanf("127", "%hhd", &narrow) == 1 && narrow == 127);
        narrow = 0;
        CHECK(sscanf("-128", "%hhd", &narrow) == 1 && narrow == -128);
    }
    CHECK(c99_scan_into("12/34", "%d/%d", &int_a, &int_b) == 2);
    CHECK(int_a == 12 && int_b == 34);
    CHECK(c99_scan_into("2.5", "%f", &float_value) == 1 && float_value == 2.5f);

    /* A real stream: writes, seeks, character input, error and EOF state. */
    {
        FILE *fp = tmpfile();
        char line[32];
        fpos_t position;

        if (fp != NULL) {
            CHECK(fputs("first\n", fp) >= 0);
            CHECK(fprintf(fp, "%s-%d\n", "second", 2) == 9);
            CHECK(fputc('X', fp) == 'X');
            CHECK(fflush(fp) == 0);
            CHECK(fgetpos(fp, &position) == 0);
            CHECK(fseek(fp, 0L, SEEK_SET) == 0);
            CHECK(ftell(fp) == 0L);
            CHECK(fgets(line, sizeof line, fp) == line);
            CHECK(strcmp(line, "first\n") == 0);
            CHECK(fgets(line, sizeof line, fp) == line);
            CHECK(strcmp(line, "second-2\n") == 0);
            CHECK(getc(fp) == 'X');
            CHECK(ungetc('Y', fp) == 'Y');
            CHECK(getc(fp) == 'Y');
            CHECK(feof(fp) == 0);
            CHECK(getc(fp) == EOF);
            CHECK(feof(fp) != 0);
            clearerr(fp);
            CHECK(feof(fp) == 0 && ferror(fp) == 0);
            CHECK(fread(line, 1, 1, fp) == 0);      /* still at end of file */
            CHECK(feof(fp) != 0);
            clearerr(fp);
            CHECK(fsetpos(fp, &position) == 0);
            CHECK(fwrite("abc", 1, 3, fp) == 3);
            CHECK(ftell(fp) == 19L);
            CHECK(fseek(fp, 0L, SEEK_END) == 0);
            CHECK(ftell(fp) == 19L);
            CHECK(fseek(fp, 0L, SEEK_SET) == 0);
            CHECK(fread(line, 1, 19, fp) == 19);
            CHECK(feof(fp) == 0);                   /* exactly consumed */
            CHECK(line[0] == 'f' && line[18] == 'c');
            rewind(fp);
            CHECK(ftell(fp) == 0L && feof(fp) == 0);
            CHECK(fread(line, 1, 5, fp) == 5);
            CHECK(memcmp(line, "first", 5) == 0);
            CHECK(fclose(fp) == 0);
        }

        /* A second stream: setbuf must be called before any I/O, and its array
         * must be at least BUFSIZ bytes (C99 7.19.5.5p2 with 7.19.5.6p3). */
        fp = tmpfile();
        if (fp != NULL) {
            static char buffer_storage[BUFSIZ];
            CHECK(sizeof buffer_storage >= (size_t)BUFSIZ);
            setbuf(fp, buffer_storage);
            CHECK(fputs("10 20 30\n", fp) >= 0);
            CHECK(fflush(fp) == 0);
            rewind(fp);
            CHECK(fscanf(fp, "%d %d %d", &int_a, &int_b, &consumed) == 3);
            CHECK(int_a == 10 && int_b == 20 && consumed == 30);
            CHECK(fclose(fp) == 0);
        }
    }

    /* Named files: fopen, rename, remove, and the error path with perror
     * (which writes exactly one line to stderr). */
    {
        const char *name_a = "c99_stdio_tmp.txt";
        const char *name_b = "c99_stdio_tmp_renamed.txt";
        FILE *fp = fopen(name_a, "w");

        if (fp != NULL) {
            CHECK(fputs("data", fp) >= 0);
            CHECK(fclose(fp) == 0);
            CHECK(rename(name_a, name_b) == 0);
            fp = fopen(name_b, "r");
            CHECK(fp != NULL);
            if (fp != NULL) {
                CHECK(fgetc(fp) == 'd');
                CHECK(fclose(fp) == 0);
            }
            CHECK(remove(name_b) == 0);
            CHECK(remove(name_b) != 0);         /* already gone */
        }

        errno = 0;
        CHECK(fopen("c99_no_such_directory_deadbeef/x", "r") == NULL);
        CHECK(errno != 0);
        /* errno is left set here so that perror prints the real text; the
         * line it writes goes to stderr. */
        perror("expected failure (this line is intentional)");
        errno = 0;
    }

    return g_fail - failures;
}

/* ==========================================================================
 * 16 general utilities: allocation, sorting, conversions, program control
 * ========================================================================== */

static int c99_compare_pairs(const void *lhs, const void *rhs)
{
    const c99_pair_t *a = lhs;
    const c99_pair_t *b = rhs;

    if (a->a != b->a) {
        return a->a < b->a ? -1 : 1;
    }
    if (a->b != b->b) {
        return a->b < b->b ? -1 : 1;
    }
    return 0;
}

static int c99_compare_ints(const void *lhs, const void *rhs)
{
    int a = *(const int *)lhs;
    int b = *(const int *)rhs;

    return (a > b) - (a < b);
}

static int c99_atexit_runs;

static void c99_remember_atexit(void)
{
    ++c99_atexit_runs;
}

static int sec_16_utilities(void)
{
    int failures = g_fail;
    int *heap = malloc(10 * sizeof *heap);
    int *zeroed = calloc(10, sizeof *zeroed);
    int sorted[7] = {7, 1, 5, 3, 2, 6, 4};
    c99_pair_t pairs[4] = {{2, 9}, {1, 2}, {2, 3}, {1, 5}};
    char *end_pointer = NULL;
    /* Read at run time so that no optimizer can prove anything about the
     * allocation below from the value alone. */
    size_t huge_size = (size_t)strtoumax("18446744073709551615", NULL, 10);
    char *environment = getenv("PATH");

    sec_begin("16 general utilities");

    /* malloc, calloc, realloc, free. */
    CHECK(heap != NULL && zeroed != NULL);
    if (heap != NULL) {
        for (int i = 0; i < 10; ++i) {
            heap[i] = i * i;
        }
        CHECK(heap[9] == 81);
        heap = realloc(heap, 20 * sizeof *heap);
        CHECK(heap != NULL);
        if (heap != NULL) {
            CHECK(heap[9] == 81);              /* contents preserved */
            heap[19] = 999;
            CHECK(heap[19] == 999);
        }
        free(heap);
    }
    if (zeroed != NULL) {
        CHECK(zeroed[0] == 0 && zeroed[9] == 0);
        zeroed = realloc(zeroed, 4 * sizeof *zeroed);   /* shrink */
        CHECK(zeroed != NULL);
        free(zeroed);
    }
    free(NULL);                                /* free(NULL) does nothing */
    CHECK(realloc(NULL, 4) != NULL);
    {
        /* realloc(ptr, 0) may return NULL or a pointer that must be freed. */
        void *shrunk_to_nothing = realloc(malloc(8), 0);
        free(shrunk_to_nothing);
    }
    {
        /* An impossible size must fail cleanly rather than crash.  C99 does
         * not require errno to be set for allocation failures, and an
         * optimizer may fold away a malloc/free pair whose result it can
         * predict, so the call goes through a volatile function pointer to
         * keep the real allocation. */
        void *(*volatile allocate)(size_t) = malloc;
        void *impossible;
        CHECK(huge_size > (size_t)PTRDIFF_MAX);
        impossible = allocate(huge_size);
        CHECK(impossible == NULL);
        free(impossible);
    }

    /* qsort and bsearch. */
    qsort(sorted, 7, sizeof sorted[0], c99_compare_ints);
    CHECK(sorted[0] == 1 && sorted[3] == 4 && sorted[6] == 7);
    {
        int key = 5;
        int *found = bsearch(&key, sorted, 7, sizeof sorted[0], c99_compare_ints);
        CHECK(found != NULL && *found == 5);
        key = 100;
        CHECK(bsearch(&key, sorted, 7, sizeof sorted[0], c99_compare_ints) == NULL);
    }
    qsort(pairs, 4, sizeof pairs[0], c99_compare_pairs);
    CHECK(pairs[0].a == 1 && pairs[0].b == 2);
    CHECK(pairs[1].a == 1 && pairs[1].b == 5);
    CHECK(pairs[2].a == 2 && pairs[2].b == 3);
    CHECK(pairs[3].a == 2 && pairs[3].b == 9);
    {
        c99_pair_t key = {2, 3};
        c99_pair_t *found = bsearch(&key, pairs, 4, sizeof pairs[0], c99_compare_pairs);
        CHECK(found != NULL && found->a == 2 && found->b == 3);
    }

    /* Integer arithmetic helpers; lldiv/imaxdiv/imaxabs are C99. */
    CHECK(abs(-5) == 5 && labs(-5L) == 5L && llabs(-5LL) == 5LL);
    {
        div_t dq = div(17, 5);
        ldiv_t ldq = ldiv(17L, 5L);
        lldiv_t lldq = lldiv(17LL, 5LL);
        imaxdiv_t idq = imaxdiv((intmax_t)17, (intmax_t)5);
        CHECK(dq.quot == 3 && dq.rem == 2);
        CHECK(ldq.quot == 3L && ldq.rem == 2L);
        CHECK(lldq.quot == 3LL && lldq.rem == 2LL);
        CHECK(idq.quot == 3 && idq.rem == 2);
        CHECK(imaxabs((intmax_t)-5) == 5);
    }

    /* rand and srand: the same seed must give the same sequence. */
    {
        int first[4], second[4];
        srand(1);
        for (int i = 0; i < 4; ++i) {
            first[i] = rand();
        }
        srand(1);
        for (int i = 0; i < 4; ++i) {
            second[i] = rand();
        }
        CHECK(first[0] == second[0] && first[3] == second[3]);
        CHECK(first[0] >= 0 && first[0] <= RAND_MAX);
        srand((unsigned)time(NULL));
        CHECK(rand() >= 0 && rand() <= RAND_MAX);
        CHECK(RAND_MAX >= 32767);
    }

    /* String-to-number conversions, including the C99 additions. */
    CHECK(atof("2.5") == 2.5 && atoi("42") == 42);
    CHECK(atol("42") == 42L && atoll("42") == 42LL);
    CHECK(atof("") == 0.0 && atoi("x") == 0);
    CHECK(strtod("2.5", NULL) == 2.5);
    CHECK(strtof("2.5", NULL) == 2.5f);
    CHECK(strtold("2.5", NULL) == 2.5L);
    CHECK(strtod("0x1p2", NULL) == 4.0);        /* hex float, C99 */
    CHECK(strtod("inf", NULL) > DBL_MAX);
    CHECK(isnan(strtod("nan", NULL)));
    CHECK(strtol("42", NULL, 10) == 42L);
    CHECK(strtol("0x2a", NULL, 16) == 42L);
    CHECK(strtol("0x2a", NULL, 0) == 42L);      /* base 0 detects 0x/0 */
    CHECK(strtol("052", NULL, 0) == 42L);
    CHECK(strtoll("-9223372036854775807", NULL, 10) == LLONG_MIN + 1);
    CHECK(strtoul("4294967295", NULL, 10) == 4294967295UL);
    CHECK(strtoull("18446744073709551615", NULL, 10) == ULLONG_MAX);
    CHECK(strtol("   -42xyz", &end_pointer, 10) == -42L);
    CHECK(end_pointer != NULL && *end_pointer == 'x');
    CHECK(strtoimax("-9", NULL, 10) == (intmax_t)-9);
    CHECK(strtoumax("9", NULL, 10) == (uintmax_t)9);
    CHECK(strtof("1e40", NULL) == HUGE_VALF);   /* float overflow */

    /* Overflow sets ERANGE; a negative value for an unsigned conversion
     * wraps (C99). */
    errno = 0;
    CHECK(strtol("999999999999999999999999", NULL, 10) == LONG_MAX);
    CHECK(errno == ERANGE);
    errno = 0;
    CHECK(strtod("1e-9999", NULL) == 0.0);
    CHECK(errno == ERANGE);
    errno = 0;
    CHECK(strtoul("-1", NULL, 10) == ULONG_MAX);
    errno = 0;

    /* getenv, system(NULL): no command is run, only the availability of a
     * command processor is reported. */
    CHECK(environment == NULL || strlen(environment) > 0);
    CHECK(getenv("C99_CERTAINLY_NOT_SET_12345") == NULL);
    {
        /* system(NULL) reports whether a command processor exists without
         * running anything. */
        int command_processor = system(NULL);
        CHECK(command_processor == 0 || command_processor == 1);
    }
    /* atexit: the handler runs after main returns; see the end of the file. */
    CHECK(atexit(c99_remember_atexit) == 0);
    CHECK(EXIT_SUCCESS == 0 && EXIT_FAILURE != 0);

    return g_fail - failures;
}

/* ==========================================================================
 * 17 time, locale, signals, non-local jumps, errno, assert
 * ========================================================================== */

static volatile sig_atomic_t c99_signal_seen;
static jmp_buf c99_jump_buffer;

static void c99_signal_handler(int signum)
{
    c99_signal_seen = signum;      /* sig_atomic_t is the only safe update */
}

/* longjmp from three nested calls: the frames in between are discarded.  Three
 * distinct functions are used rather than one recursive helper so that no
 * compiler diagnoses self-recursion here. */
static void c99_jump_level3(int value)
{
    longjmp(c99_jump_buffer, value);   /* does not return */
}

static void c99_jump_level2(int value)
{
    c99_jump_level3(value);
}

static void c99_jump_level1(int value)
{
    c99_jump_level2(value);
}

/* The value passed to longjmp arrives as setjmp's result.  C99 7.13.1.1
 * restricts where setjmp may appear: a switch or if controlling expression. */
static int c99_setjmp_value(void)
{
    volatile int observed = -1;

    switch (setjmp(c99_jump_buffer)) {
    case 0:
        c99_jump_level1(42);            /* three frames deep */
        break;                          /* not reached */
    case 42:
        observed = 42;
        break;
    default:
        observed = -2;
        break;
    }
    return observed;
}

/* Only objects with volatile-qualified type are guaranteed to survive a
 * longjmp, so the variables here are volatile. */
static int c99_setjmp_survives(void)
{
    volatile int stage = 0;
    volatile int survived = -1;

    if (setjmp(c99_jump_buffer) == 0) {
        stage = 1;
        c99_jump_level1(1);
        stage = 99;                     /* not reached */
    } else {
        survived = stage;
    }
    return survived == 1 ? 1 : 0;
}

static int sec_17_runtime(void)
{
    int failures = g_fail;

    sec_begin("17 time, locale, signals, setjmp, errno, assert");

    /* <time.h>.  gmtime, localtime, asctime and ctime may share one static
     * buffer, so each result is copied before the next call can overwrite it. */
    {
        time_t epoch_zero = 0;
        time_t now = time(NULL);
        struct tm epoch_fields;
        struct tm local_fields;
        struct tm *epoch_result = gmtime(&epoch_zero);
        struct tm *local_result;
        int have_epoch = 0;
        int have_local = 0;
        char stamp[64];
        clock_t ticks = clock();

        if (epoch_result != NULL) {
            epoch_fields = *epoch_result;      /* copy before anything else */
            have_epoch = 1;
        }
        local_result = localtime(&now);
        if (local_result != NULL) {
            local_fields = *local_result;
            have_local = 1;
        }

        CHECK(now > 0);
        CHECK(have_epoch == 1);
        if (have_epoch) {
            CHECK(epoch_fields.tm_year == 70 && epoch_fields.tm_mon == 0);
            CHECK(epoch_fields.tm_mday == 1);
            CHECK(epoch_fields.tm_wday == 4 && epoch_fields.tm_yday == 0);
            CHECK(epoch_fields.tm_hour == 0 && epoch_fields.tm_min == 0);
            CHECK(epoch_fields.tm_sec == 0 && epoch_fields.tm_isdst == 0);
            {
                char utc_text[32];
                char local_text[32];
                snprintf(utc_text, sizeof utc_text, "%s", asctime(&epoch_fields));
                CHECK(strcmp(utc_text, "Thu Jan  1 00:00:00 1970\n") == 0);
                /* ctime is asctime(localtime(t)): the calendar date depends on
                 * the local offset, so only the shape is checked. */
                snprintf(local_text, sizeof local_text, "%s", ctime(&epoch_zero));
                CHECK(strlen(local_text) == 25);
                CHECK(local_text[24] == '\n');
                CHECK(local_text[3] == ' ' && local_text[7] == ' ');
                CHECK(local_text[10] == ' ' && local_text[19] == ' ');
                CHECK(strchr("SMFTW", local_text[0]) != NULL);
            }
            CHECK(strftime(stamp, sizeof stamp, "%Y-%m-%d %H:%M:%S",
                           &epoch_fields) == 19);
            CHECK(strcmp(stamp, "1970-01-01 00:00:00") == 0);
            CHECK(strftime(stamp, sizeof stamp, "%j %U %w", &epoch_fields) == 8);
            CHECK(strcmp(stamp, "001 00 4") == 0);
            /* A buffer too small for the result plus its terminator makes
             * strftime return 0; the contents are then unspecified. */
            CHECK(strftime(stamp, 4, "%Y-%m-%d", &epoch_fields) == 0);
        }
        if (have_local) {
            CHECK(local_fields.tm_year >= 70);
            CHECK(local_fields.tm_mon >= 0 && local_fields.tm_mon <= 11);
            CHECK(local_fields.tm_mday >= 1 && local_fields.tm_mday <= 31);
            CHECK(local_fields.tm_hour >= 0 && local_fields.tm_hour <= 23);
            CHECK(local_fields.tm_min >= 0 && local_fields.tm_min <= 59);
            CHECK(local_fields.tm_sec >= 0 && local_fields.tm_sec <= 60);
            CHECK(local_fields.tm_isdst >= -1 && local_fields.tm_isdst <= 1);
        }
        /* mktime and localtime are inverses for a wall-clock time built from
         * UTC fields, whatever the local time-zone offset is. */
        if (have_epoch) {
            struct tm rebuilt_fields = epoch_fields;
            time_t rebuilt = mktime(&rebuilt_fields);
            struct tm *again = localtime(&rebuilt);

            CHECK(rebuilt != (time_t)-1);
            CHECK(again != NULL);
            if (again != NULL) {
                CHECK(again->tm_year == 70 && again->tm_mon == 0);
                CHECK(again->tm_mday == 1 && again->tm_hour == 0);
            }
            CHECK(difftime(rebuilt, epoch_zero) == (double)(rebuilt - epoch_zero));
            CHECK(difftime(epoch_zero, rebuilt) == -difftime(rebuilt, epoch_zero));
        }
        CHECK(ticks >= (clock_t)0);
        CHECK(CLOCKS_PER_SEC > 0);
        CHECK(time(NULL) >= now);
    }

    /* <locale.h>: setlocale and localeconv.  The environment locale is put
     * back afterwards so the ctype expectations above stay valid. */
    {
        const char *current = setlocale(LC_ALL, NULL);
        char saved[64];
        struct lconv *conv;

        CHECK(current != NULL);
        snprintf(saved, sizeof saved, "%s", current != NULL ? current : "C");
        CHECK(setlocale(LC_ALL, "") != NULL);
        CHECK(setlocale(LC_ALL, "C") != NULL);
        CHECK(strcmp(setlocale(LC_ALL, NULL), "C") == 0);
        CHECK(setlocale(LC_NUMERIC, "C") != NULL);
        CHECK(setlocale(LC_ALL, saved) != NULL);
        CHECK(setlocale(LC_COLLATE, NULL) != NULL);
        CHECK(setlocale(LC_CTYPE, NULL) != NULL);
        CHECK(setlocale(LC_MONETARY, NULL) != NULL);
        CHECK(setlocale(LC_TIME, NULL) != NULL);
        CHECK(setlocale(LC_ALL, "C") != NULL);   /* deterministic from here on */

        conv = localeconv();
        CHECK(conv != NULL);
        if (conv != NULL) {
            int frac_digits = conv->frac_digits;
            int p_cs_precedes = conv->p_cs_precedes;
            int n_sign_posn = conv->n_sign_posn;
            int p_sep_by_space = conv->p_sep_by_space;
            CHECK(conv->decimal_point != NULL && conv->decimal_point[0] != '\0');
            CHECK(strcmp(conv->decimal_point, ".") == 0);   /* the C locale */
            CHECK(conv->thousands_sep != NULL);
            CHECK(conv->grouping != NULL);
            CHECK(conv->currency_symbol != NULL);
            CHECK(conv->int_curr_symbol != NULL);
            CHECK(conv->mon_decimal_point != NULL);
            CHECK(conv->mon_thousands_sep != NULL);
            CHECK(conv->mon_grouping != NULL);
            CHECK(conv->positive_sign != NULL && conv->negative_sign != NULL);
            CHECK(frac_digits >= -128 && frac_digits <= 127);
            CHECK(p_cs_precedes >= -128 && p_cs_precedes <= 127);
            CHECK(n_sign_posn >= -128 && n_sign_posn <= 127);
            CHECK(p_sep_by_space >= -128 && p_sep_by_space <= 127);
        }
    }

    /* <signal.h> */
    CHECK(SIG_DFL != SIG_IGN && SIG_ERR != SIG_DFL && SIG_ERR != SIG_IGN);
#ifdef SIGUSR1
    {
        void (*previous)(int);

        CHECK(signal(SIGUSR1, SIG_IGN) != SIG_ERR);
        CHECK(raise(SIGUSR1) == 0);          /* ignored: no effect */
        c99_signal_seen = 0;
        previous = signal(SIGUSR1, c99_signal_handler);
        CHECK(previous != SIG_ERR);
        CHECK(raise(SIGUSR1) == 0);
        CHECK(c99_signal_seen == SIGUSR1);
        CHECK(signal(SIGUSR1, SIG_DFL) != SIG_ERR);
    }
#else
    CHECK(1);                                /* SIGUSR1 is not available */
#endif

    /* <setjmp.h> */
    CHECK(c99_setjmp_value() == 42);
    CHECK(c99_setjmp_survives() == 1);

    /* <errno.h>: errno is a modifiable lvalue; EILSEQ is a C99 addition. */
    errno = 0;
    CHECK(errno == 0);
    errno = EDOM;
    CHECK(errno == EDOM);
    errno = ERANGE;
    CHECK(errno == ERANGE);
    errno = EILSEQ;
    CHECK(errno == EILSEQ);
    CHECK(EDOM != ERANGE && ERANGE != EILSEQ);
    CHECK(strerror(EILSEQ) != NULL);
    errno = 0;
    (void)strtol("x", NULL, 10);
    CHECK(errno == 0);                       /* no conversion: no error set */

    /* <assert.h>.  assert(0) is not exercised: it would abort the run. */
    assert(1);
    assert(sizeof(int) >= 2);
    {
        int value = 5;
        assert(value > 0);
        assert(value == 5 && "assert is live: NDEBUG was dropped");
    }
    CHECK(1);                                /* no assertion fired */

    return g_fail - failures;
}

/* ==========================================================================
 * 18 flag-dependent and optional C99 material
 *
 * The constructs below are standard C99 but need a non-default compiler
 * switch or an optional implementation feature, so they stay out of the
 * default build:
 *
 *   - trigraphs (removed again in C23)        -DC99_TRIGRAPHS, together with
 *                                             -Wno-trigraphs
 *   - brace elision in a nested initializer    -DC99_BRACE_ELISION, together
 *                                             with -Wno-missing-braces
 *   - imaginary types                         optional; neither GCC nor Clang
 *                                             implements them at all
 *   - overlong string literals                -DC99_OVERLONG_STRINGS, together
 *                                             with -Wno-overlength-strings
 *   - re-entering the source through __FILE__ -DC99_TEST_SELF_INCLUDE
 *
 * Deliberately NOT used anywhere in this file, because they are compiler
 * extensions rather than C99: statement expressions, typeof, nested
 * functions, __attribute__, designated-initializer ranges ([0 ... 3]),
 * anonymous struct/union members (C11), and the C11/C23 library additions.
 *
 * The only pragmas left are the three standard C99 ones from 6.10.6 (STDC
 * FP_CONTRACT, STDC FENV_ACCESS, STDC CX_LIMITED_RANGE, written once in both
 * their #pragma and _Pragma forms); there are no vendor diagnostic pragmas,
 * and nothing here relies on a compiler-specific option to build or to pass.
 * ========================================================================== */

#ifdef C99_TRIGRAPHS
/* ??= is #, ??( and ??) are brackets, ??< and ??> are braces, ??! is |,
 * ??' is ^, ??- is ~, and ??/ acts as a backslash (so it continues a line). */
??=define C99_TRIGRAPH_MACRO 1 ??/
    + 2

static int sec_18_trigraphs(void)
{
    int failures = g_fail;
    int values??(3??) = ??< 10, 20, 30 ??>;
    int mask = 0x05;

    sec_begin("18 trigraphs (built with -DC99_TRIGRAPHS)");

    CHECK(C99_TRIGRAPH_MACRO == 3);
    CHECK(values??(0??) == 10 ??!??! values??(2??) == 30);
    CHECK(sizeof values == 3 * sizeof(int));
    CHECK((??- mask) == ~0x05);               /* ??- is ~ */
    CHECK((mask ??' 0x03) == (0x05 ^ 0x03));   /* ??' is ^ */

    return g_fail - failures;
}
#endif /* C99_TRIGRAPHS */

/* Imaginary types are optional in C99 and are genuinely rare: both GCC and
 * Clang define __STDC_IEC_559_COMPLEX__ = 1 yet reject _Imaginary outright, so
 * this block needs its own macro.  Build with -DC99_IMAGINARY on a compiler
 * that implements them (its <complex.h> must also define _Imaginary_I). */
#ifdef C99_IMAGINARY
static int sec_18_imaginary(void)
{
    int failures = g_fail;
    double _Imaginary imaginary_unit = 1.0 * _Imaginary_I;
    double _Complex square = imaginary_unit * imaginary_unit;

    sec_begin("18 imaginary types");

    CHECK(creal(square) == -1.0 && cimag(square) == 0.0);
    CHECK(sizeof(double _Imaginary) == sizeof(double));
    CHECK(sizeof(float _Imaginary) == sizeof(float));
    CHECK(sizeof(long double _Imaginary) == sizeof(long double));

    return g_fail - failures;
}
#endif

/* ==========================================================================
 * 15b stdio, part two: input from a file, and output redirected with freopen
 *
 * This runs after the summary line because the second half repoints stdout;
 * failures there are reported on stderr and only the exit status carries
 * them.
 * ========================================================================== */

static int sec_15b_redirected_stdio(void)
{
    const char *input_name = "c99_stdio_input.txt";
    const char *output_name = "c99_stdio_output.txt";
    int failures = g_fail;
    int first = 0, second = 0;
    char line[16];
    FILE *file;

    /* Point stdin at a real file: scanf, getchar and fgets all read from it. */
    file = fopen(input_name, "w");
    if (file != NULL) {
        fputs("7 8\nZ\n", file);
        fclose(file);

        if (freopen(input_name, "r", stdin) != NULL) {
            sec_begin("15b stdin redirected with freopen");
            CHECK(scanf("%d %d", &first, &second) == 2);
            CHECK(first == 7 && second == 8);
            CHECK(getchar() == '\n');      /* the whitespace scanf left */
            CHECK(getchar() == 'Z');
            CHECK(getchar() == '\n');      /* the newline after Z */
            CHECK(getchar() == EOF);
            CHECK(feof(stdin) != 0);
            clearerr(stdin);
            CHECK(fgets(line, sizeof line, stdin) == NULL);
        }
        remove(input_name);
    }

    /* Point stdout at a file and check what lands in it. */
    file = freopen(output_name, "w", stdout);
    if (file != NULL) {
        int written;

        printf("%s", "redirected");
        putchar('!');
        fputs(" done\n", stdout);
        fflush(stdout);
        written = fprintf(stdout, "%d\n", 42);
        fclose(stdout);

        file = fopen(output_name, "r");
        if (file != NULL) {
            char content[64];
            size_t read_bytes = fread(content, 1, sizeof content - 1, file);
            content[read_bytes] = '\0';
            fclose(file);
            if (written != 3 || strcmp(content, "redirected! done\n42\n") != 0) {
                fprintf(stderr, "FAIL: redirected stdout content was %s", content);
                ++g_fail;
            } else {
                fprintf(stderr,
                        "stdout redirection via freopen verified: %s",
                        content);
            }
        } else {
            fprintf(stderr, "FAIL: could not reopen %s\n", output_name);
            ++g_fail;
        }
        remove(output_name);
    }

    return g_fail - failures;
}

static void sec_19_line_directive(void);

/* Registered by main before any section runs.  atexit handlers run in reverse
 * order of registration, so this one runs last and can also check that the
 * handler registered by section 16 already ran exactly once. */
static int c99_atexit_main_runs;

static void c99_atexit_handler(void)
{
    ++c99_atexit_main_runs;
    /* Handlers run after main returns, when stdout may already have been
     * repointed by the freopen test, so this reports on stderr. */
    if (c99_atexit_main_runs != 1) {
        fprintf(stderr, "FAIL: main's atexit handler ran %d times\n",
                c99_atexit_main_runs);
    } else if (c99_atexit_runs != 1) {
        fprintf(stderr, "FAIL: section 16's atexit handler ran %d times\n",
                c99_atexit_runs);
    } else {
        fprintf(stderr,
                "both atexit handlers ran exactly once, after main returned\n");
    }
}

int main(int argc, char **argv)
{
    int atexit_registered;

    printf("C99 coverage corpus: __STDC_VERSION__ = %ldL, __STDC__ = %d, %s\n",
           (long)__STDC_VERSION__, __STDC__,
           __STDC_HOSTED__ ? "hosted" : "freestanding");
    if (argc > 0 && argv != NULL && argv[0] != NULL) {
        printf("argv[0] = %s, argc = %d\n", argv[0], argc);
    }

    atexit_registered = atexit(c99_atexit_handler);
    if (atexit_registered != 0) {
        ++g_fail;
        fprintf(stderr, "FAIL: atexit could not register the handler\n");
    }

    sec_01_preprocessor();
    sec_02_lexical();
    sec_03_translation_limits();
    sec_04_declarations();
    sec_05_types();
    sec_06_expressions();
    sec_07_control_flow();
    sec_08_functions();
    sec_09_aggregates();
    sec_10_arrays();
    sec_11_pointers();
    sec_12_characters();
    sec_13_strings();
    sec_14_numerics();
    sec_15_stdio();
#ifdef C99_TRIGRAPHS
    sec_18_trigraphs();
#endif

    sec_16_utilities();
    sec_17_runtime();
#ifdef C99_IMAGINARY
    sec_18_imaginary();
#endif

    sec_19_line_directive();
    if (g_section_checks != 0) {
        printf("    (%d checks)\n", g_section_checks);
    }
    printf("\n%d checks, %d passed, %d failed\n", g_checks, g_pass, g_fail);

    /* Runs last: it repoints stdout, so anything it prints goes to a file. */
    (void)sec_15b_redirected_stdio();

    return g_fail > 125 ? 125 : g_fail;
}

/* ==========================================================================
 * 19 the #line directive
 *
 * Placed after main on purpose: #line renumbers the rest of the translation
 * unit, so everything below it would otherwise report misleading line
 * numbers in failure messages.
 * ========================================================================== */

static void sec_19_line_directive(void)
{
    sec_begin("19 #line directive");
#line 4242 "c99-line-directive.h"
    CHECK(__LINE__ == 4242);
    CHECK(strcmp(__FILE__, "c99-line-directive.h") == 0);
#line 7
    CHECK(__LINE__ == 7);                    /* the file name is kept */
    CHECK(strcmp(__FILE__, "c99-line-directive.h") == 0);
#line 1 "main.c"
    CHECK(__LINE__ == 1);
    CHECK(strcmp(__FILE__, "main.c") == 0);
}

#endif /* C99_MAIN_C */


