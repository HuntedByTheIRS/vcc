/* 1128: a-function-defined-inside-another-function
 *
 * GCC 6.12.4 Nested Functions: "A nested function is a function defined inside
 * another function. ... The nested function can access all the variables of the
 * containing function that are visible at the point of its definition. This is
 * called lexical scoping."
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
    int offset = 5;

    int square(int z) { return z * z; }
    int add(int v) { return v + offset; }

    CHECK(square(4) == 16);
    CHECK(add(1) == 6);
    CHECK(square(add(2)) == 49);
    return 0;
}
