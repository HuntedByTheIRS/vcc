/* 218: CHECK(from_negative == UINT_MAX);
 *
 * monolithic.c:9988 (expressions)
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
    CHECK(from_negative == UINT_MAX);
    }
    return 0;
}
