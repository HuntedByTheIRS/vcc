/* 242: CHECK((*fp)(1, 2) == 3);
 *
 * monolithic.c:10030 (expressions)
 */

#include <stdio.h>

static int c99_add(int x, int y) { return x + y; }

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    {
    int (*fp)(int, int) = c99_add;
    CHECK((*fp)(1, 2) == 3);
    }
    return 0;
}
