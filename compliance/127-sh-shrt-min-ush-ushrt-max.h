/* 127: CHECK(sh == SHRT_MIN && ush == USHRT_MAX);
 *
 * monolithic.c:9805 (types)
 */

#include <stdio.h>
#include <limits.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    short sh = SHRT_MIN;
    unsigned short ush = USHRT_MAX;
    CHECK(sh == SHRT_MIN && ush == USHRT_MAX);
    return 0;
}
