/* 0093: CHECK(ops[1](3, 4) == 12);
 *
 * monolithic.c:9667 (declarations)
 */

#include <stdio.h>

typedef int (*c99_binop_t)(int, int);

static int c99_add(int x, int y) { return x + y; }

static int c99_mul(int x, int y) { return x * y; }

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    c99_binop_t ops[2];
    ops[0] = c99_add;
    ops[1] = c99_mul;
    CHECK(ops[0](3, 4) == 7);
    CHECK(ops[1](3, 4) == 12);
    return 0;
}
