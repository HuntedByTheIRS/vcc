/* 0816: CHECK(strtoull("18446744073709551615", NULL, 10) == ULLONG_MAX);
 *
 * monolithic.c:11801 (utilities)
 */

#include <stdio.h>
#include <limits.h>
#include <stddef.h>
#include <stdlib.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(strtoull("18446744073709551615", NULL, 10) == ULLONG_MAX);
    return 0;
}
