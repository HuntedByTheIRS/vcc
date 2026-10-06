/* 0220: CHECK(from_negative + 1u == 0u);
 *
 * monolithic.c:9990 (expressions)
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
    {
    int minus_one = -1;
    unsigned int from_negative = minus_one;
    unsigned int from_cast = (unsigned)-1;
    CHECK(from_negative == UINT_MAX);
    CHECK(from_cast == from_negative);
    CHECK(from_negative + 1u == 0u);
    }
    return 0;
}
