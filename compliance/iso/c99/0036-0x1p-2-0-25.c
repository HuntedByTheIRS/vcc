/* 0036: CHECK(0x1p-2 == 0.25);
 *
 * monolithic.c:295 (lexical)
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
    CHECK(0x1p-2 == 0.25);
    return 0;
}
