/* 106: CHECK(reg * 2 == 8);
 *
 * monolithic.c:9705 (declarations)
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
    {
    register int reg = 4;
    CHECK(reg * 2 == 8);
    }
    return 0;
}
