/* 0338: CHECK(from_enum[0][0] == 0 && from_enum[1][2] == 0);
 *
 * monolithic.c:10648 (arrays)
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
    int from_enum[ROWS][COLS] = {{0}};
    CHECK(from_enum[0][0] == 0 && from_enum[1][2] == 0);
    return 0;
}
