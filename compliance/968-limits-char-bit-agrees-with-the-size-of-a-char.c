/* 968: CHECK(CHAR_BIT == 8 && sizeof(char) == 1);
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
    CHECK(CHAR_BIT == 8);
    CHECK(sizeof(char) == 1);
    CHECK(sizeof(short) * CHAR_BIT == 16);
    CHECK(sizeof(int) * CHAR_BIT == 32);
    CHECK(sizeof(long long) * CHAR_BIT == 64);
    return 0;
}
