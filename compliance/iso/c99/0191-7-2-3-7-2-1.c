/* 0191: CHECK(-7 / 2 == -3 && -7 % 2 == -1);
 *
 * monolithic.c:9945 (expressions)
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
    CHECK(-7 / 2 == -3 && -7 % 2 == -1);
    return 0;
}
