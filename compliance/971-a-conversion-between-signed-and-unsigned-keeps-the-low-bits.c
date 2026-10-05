/* 971: CHECK((unsigned)-1 == UINT_MAX);
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
    CHECK((unsigned int)-1 == UINT_MAX);
    CHECK((unsigned int)-2 == UINT_MAX - 1u);
    CHECK((int)UINT_MAX == -1);
    CHECK((int)2147483648u == INT_MIN);
    CHECK((unsigned int)INT_MAX == 2147483647u);
    return 0;
}
