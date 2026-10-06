/* 0174: CHECK(e == 2 && SMALL_THREE == 3);
 *
 * monolithic.c:9875 (types)
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
    enum c99_small { SMALL_ONE = 1, SMALL_TWO, SMALL_THREE, } e = SMALL_TWO;
    CHECK(e == 2 && SMALL_THREE == 3);
    }
    return 0;
}
