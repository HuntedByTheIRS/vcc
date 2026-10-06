/* 0129: CHECK(CHAR_BIT >= 8 && CHAR_MIN <= 0);
 *
 * monolithic.c:9807 (types)
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
    CHECK(CHAR_BIT >= 8 && CHAR_MIN <= 0);
    return 0;
}
