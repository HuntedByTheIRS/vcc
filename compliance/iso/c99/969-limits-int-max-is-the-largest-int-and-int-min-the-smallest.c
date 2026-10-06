/* 969: CHECK(INT_MAX == 2147483647);
 *
 * not in monolithic.c: added after the corpus was split, so it has no line there.
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
    CHECK(INT_MAX == 2147483647);
    CHECK(INT_MIN == -2147483647 - 1);
    CHECK(INT_MAX > 0 && INT_MIN < 0);
    CHECK(sizeof(int) == sizeof(unsigned int));
    CHECK(INT_MAX == (int)(UINT_MAX >> 1));
    CHECK(UINT_MAX == 4294967295u);
    return 0;
}
