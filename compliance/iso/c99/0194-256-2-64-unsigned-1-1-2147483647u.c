/* 0194: CHECK((256 >> 2) == 64 && ((unsigned)-1 >> 1) == 2147483647u);
 *
 * monolithic.c:9951 (expressions)
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
    CHECK((256 >> 2) == 64 && ((unsigned)-1 >> 1) == 2147483647u);
    return 0;
}
