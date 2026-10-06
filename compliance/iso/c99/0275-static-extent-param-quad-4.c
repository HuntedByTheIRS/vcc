/* 0275: CHECK(c99_static_extent_param(quad) == 4);
 *
 * monolithic.c:10398 (functions)
 */

#include <stdio.h>

static int c99_static_extent_param(const int values[static 4])
{
    return values[0] + values[1] + values[2] + values[3];
}

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    int quad[4] = {1, 1, 1, 1};
    CHECK(c99_static_extent_param(quad) == 4);
    return 0;
}
