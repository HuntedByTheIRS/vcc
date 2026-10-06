/* 336: CHECK(c99_3d[1][0][1] == 6 && c99_3d[0][1][0] == 3);
 *
 * monolithic.c:10645 (arrays)
 */

#include <stdio.h>

static int c99_3d[2][2][2] = {{{1, 2}, {3, 4}}, {{5, 6}, {7, 8}}};

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(sizeof c99_3d == 8 * sizeof(int));
    CHECK(c99_3d[1][0][1] == 6 && c99_3d[0][1][0] == 3);
    return 0;
}
