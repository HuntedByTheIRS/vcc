/* 168: CHECK(c99_tentative_definition == 9);
 *
 * monolithic.c:9861 (types)
 */

#include <stdio.h>
#include <float.h>
#include <inttypes.h>
#include <limits.h>
#include <math.h>
#include <signal.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <tgmath.h>
#include <wchar.h>

static int g_fail;

static int g_section_checks;

static void sec_begin(const char *title)
{
    if (g_section_checks != 0) {
        printf("    (%d checks)\n", g_section_checks);
    }
    g_section_checks = 0;
    printf("[%s]\n", title);
}

static long double c99_nearlyl(long double a, long double b);

static int c99_tentative_definition;

static const int c99_const_object = 7;

static long double c99_nearlyl(long double a, long double b)
{
    long double diff = fabsl(a - b);
    long double scale = fabsl(a) > fabsl(b) ? fabsl(a) : fabsl(b);
    return diff <= 1e-18L * (scale > 1.0L ? scale : 1.0L);
}

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
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
    CHECK(*pci == 7);
    *cpi = 9;
    CHECK(c99_tentative_definition == 9);
    CHECK(vci == 3);
    CHECK(sizeof(const int) == sizeof(int));
    CHECK(sizeof(volatile int) == sizeof(int));
    CHECK(bf.a == 5u && bf.c == 1u && bf.d == 1u);
    CHECK(sizeof(struct c99_bitfield) >= 2);
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
    return 0;
}
