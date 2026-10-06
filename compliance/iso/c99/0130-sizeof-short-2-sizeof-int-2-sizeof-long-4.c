/* 0130: CHECK(sizeof(short) >= 2 && sizeof(int) >= 2 && sizeof(long) >= 4);
 *
 * monolithic.c:9808 (types)
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
    CHECK(sizeof(short) >= 2 && sizeof(int) >= 2 && sizeof(long) >= 4);
    return 0;
}
