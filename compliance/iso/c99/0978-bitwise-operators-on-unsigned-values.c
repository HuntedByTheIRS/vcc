/* 0978: CHECK((a & b) == 1u);
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
    unsigned int a = 5u;
    unsigned int b = 3u;
    CHECK((a & b) == 1u);
    CHECK((a | b) == 7u);
    CHECK((a ^ b) == 6u);
    CHECK(~0u == 4294967295u);
    CHECK(~a == 4294967290u);
    CHECK((a & ~b) == 4u);
    return 0;
}
