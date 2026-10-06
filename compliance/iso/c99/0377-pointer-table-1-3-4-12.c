/* 0377: CHECK(c99_pointer_table[1](3, 4) == 12);
 *
 * monolithic.c:10793 (pointers)
 */

#include <stdio.h>

static int c99_pointer_add(int a, int b) { return a + b; }

static int c99_pointer_mul(int a, int b) { return a * b; }

static int (*const c99_pointer_table[2])(int, int) = {c99_pointer_add, c99_pointer_mul};

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(c99_pointer_table[0](3, 4) == 7);
    CHECK(c99_pointer_table[1](3, 4) == 12);
    return 0;
}
