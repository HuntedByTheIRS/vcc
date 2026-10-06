/* 0086: CHECK(c99_static_array[0] == 1 && c99_static_array[1] == 2);
 *
 * monolithic.c:9656 (declarations)
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
    return 0;
}
