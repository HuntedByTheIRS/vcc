/* 970: CHECK(UINT_MAX + 1u == 0u);
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
    unsigned int top = UINT_MAX;
    CHECK(top + 1u == 0u);
    CHECK(top * 2u == top - 1u);
    return 0;
}
