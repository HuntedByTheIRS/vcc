/* 0197: CHECK(2 + 3 == 5 && 2 != 3 && 2 < 3 && 3 > 2 && 2 <= 2 && 3 >= 3);
 *
 * monolithic.c:9954 (expressions)
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
    CHECK(2 + 3 == 5 && 2 != 3 && 2 < 3 && 3 > 2 && 2 <= 2 && 3 >= 3);
    return 0;
}
