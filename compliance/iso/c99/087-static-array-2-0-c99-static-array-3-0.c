/* 087: CHECK(c99_static_array[2] == 0 && c99_static_array[3] == 0);
 *
 * monolithic.c:9657 (declarations)
 */

#include <stdio.h>

static int c99_static_array[4] = {1, 2};

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(c99_static_array[0] == 1 && c99_static_array[1] == 2);
    CHECK(c99_static_array[2] == 0 && c99_static_array[3] == 0);
    return 0;
}
