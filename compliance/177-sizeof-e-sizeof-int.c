/* 177: CHECK(sizeof e == sizeof(int));
 *
 * monolithic.c:9878 (types)
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
    CHECK(sizeof e == sizeof(int));
    }
    return 0;
}
