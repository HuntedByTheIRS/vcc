/* 337: CHECK(sizeof c99_flat == 6 * sizeof(int) && c99_flat[5] == 6);
 *
 * monolithic.c:10646 (arrays)
 */

#include <stdio.h>

static int c99_flat[6] = {1, 2, 3, 4, 5, 6};

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(sizeof c99_flat == 6 * sizeof(int) && c99_flat[5] == 6);
    return 0;
}
