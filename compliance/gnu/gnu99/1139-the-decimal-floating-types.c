/* 1139: the-decimal-floating-types
 *
 * GCC 6.1.6 Decimal Floating Types: "The decimal floating types are _Decimal32,
 * _Decimal64, and _Decimal128. They use a radix of ten ... Use a suffix 'df' or
 * 'DF' in a literal constant of type _Decimal32, 'dd' or 'DD' for _Decimal64,
 * and 'dl' or 'DL' for _Decimal128."
 *
 * unimplemented: the decimal floating types _Decimal32, _Decimal64 and _Decimal128.
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    _Decimal32 a = 1.5df;
    _Decimal64 b = 2.5dd;
    _Decimal128 c = 3.5dl;

    CHECK(sizeof(_Decimal32) == 4);
    CHECK(sizeof(_Decimal64) == 8);
    CHECK(sizeof(_Decimal128) == 16);
    CHECK((double)a == 1.5);
    CHECK((double)b == 2.5);
    CHECK((double)c == 3.5);
    return 0;
}
