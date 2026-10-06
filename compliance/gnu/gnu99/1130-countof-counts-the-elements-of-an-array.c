/* 1130: countof-counts-the-elements-of-an-array
 *
 * GCC 6.12.6 Determining the Number of Elements of Arrays: "The keyword _Countof
 * determines the number of elements of an array operand. Its syntax is similar
 * to sizeof. The operand must be a parenthesized complete array type name or an
 * expression of such a type. ... _Countof (int [7][3]); // returns 7"
 *
 * unimplemented: _Countof.
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
    int a[7];
    char s[] = "hello";

    CHECK(_Countof(a) == 7);
    CHECK(_Countof(int[7][3]) == 7);
    CHECK(_Countof(s) == 6);
    return 0;
}
