/* 339: CHECK(ROWS == 2 && COLS == 3);
 *
 * monolithic.c:10649 (arrays)
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
    enum { ROWS = 2, COLS = 3 };
    CHECK(ROWS == 2 && COLS == 3);
    return 0;
}
