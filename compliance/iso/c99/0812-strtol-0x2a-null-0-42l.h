/* 0812: CHECK(strtol("0x2a", NULL, 0) == 42L);
 *
 * monolithic.c:11797 (utilities)
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
    CHECK(strtol("42", NULL, 10) == 42L);
    CHECK(strtol("0x2a", NULL, 16) == 42L);
    CHECK(strtol("0x2a", NULL, 0) == 42L);
    return 0;
}
