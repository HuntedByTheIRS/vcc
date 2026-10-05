/* 328: CHECK(sizeof c99_2d == 6 * sizeof(int));
 *
 * monolithic.c:10636 (arrays)
 */

#include <stdio.h>

static int c99_2d[2][3] = {{1, 2, 3}, {4, 5, 6}};

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(sizeof c99_2d == 6 * sizeof(int));
    return 0;
}
