/* 976: CHECK(1u << 31 == 2147483648u);
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
    CHECK(1 << 0 == 1);
    CHECK(1 << 10 == 1024);
    CHECK(1 << 30 == 1073741824);
    CHECK(1u << 31 == 2147483648u);
    CHECK(3u << 4 == 48u);
    return 0;
}
