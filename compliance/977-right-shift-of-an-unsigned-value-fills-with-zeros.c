/* 977: CHECK(0x80000000u >> 31 == 1u);
 *
 * not in monolithic.c: added after the corpus was split, so it has no line there.
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
    unsigned int top = 0x80000000u;
    CHECK(top >> 31 == 1u);
    CHECK(top >> 1 == 0x40000000u);
    CHECK(255u >> 4 == 15u);
    return 0;
}
