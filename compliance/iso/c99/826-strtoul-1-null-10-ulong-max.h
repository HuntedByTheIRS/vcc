/* 826: CHECK(strtoul("-1", NULL, 10) == ULONG_MAX);
 *
 * monolithic.c:11817 (utilities)
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
    CHECK(strtoul("4294967295", NULL, 10) == 4294967295UL);
    CHECK(strtoul("-1", NULL, 10) == ULONG_MAX);
    return 0;
}
