/* 807: CHECK(strtod("0x1p2", NULL) == 4.0);
 *
 * monolithic.c:11792 (utilities)
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
    CHECK(strtod("2.5", NULL) == 2.5);
    CHECK(strtod("0x1p2", NULL) == 4.0);
    return 0;
}
