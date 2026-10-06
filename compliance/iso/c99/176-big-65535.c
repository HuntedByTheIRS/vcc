/* 176: CHECK(BIG == 65535);
 *
 * monolithic.c:9877 (types)
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
    enum c99_big { BIG = 65535 };
    CHECK(BIG == 65535);
    }
    return 0;
}
