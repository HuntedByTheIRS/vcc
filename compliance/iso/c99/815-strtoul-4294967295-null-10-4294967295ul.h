/* 815: CHECK(strtoul("4294967295", NULL, 10) == 4294967295UL);
 *
 * monolithic.c:11800 (utilities)
 */

#include <stdio.h>
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
    return 0;
}
