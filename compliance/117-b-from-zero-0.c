/* 117: CHECK(b_from_zero == 0);
 *
 * monolithic.c:9794 (types)
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
    _Bool b_from_zero = 0;
    CHECK(b_from_zero == 0);
    return 0;
}
