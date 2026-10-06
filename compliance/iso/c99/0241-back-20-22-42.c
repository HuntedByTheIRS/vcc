/* 0241: CHECK(back(20, 22) == 42);
 *
 * monolithic.c:10029 (expressions)
 */

#include <stdio.h>

typedef int (*c99_binop_t)(int, int);

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
    void (*generic)(void) = (void (*)(void))fp;
    c99_binop_t back = (c99_binop_t)generic;
    CHECK(back(20, 22) == 42);
    }
    return 0;
}
