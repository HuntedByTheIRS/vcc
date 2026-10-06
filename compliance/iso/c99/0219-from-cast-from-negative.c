/* 0219: CHECK(from_cast == from_negative);
 *
 * monolithic.c:9989 (expressions)
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
    }
    return 0;
}
