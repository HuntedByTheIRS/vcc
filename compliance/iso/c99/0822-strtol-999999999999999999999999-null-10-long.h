/* 0822: CHECK(strtol("999999999999999999999999", NULL, 10) == LONG_MAX);
 *
 * monolithic.c:11811 (utilities)
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
    char *end_pointer = NULL;
    CHECK(strtol("42", NULL, 10) == 42L);
    CHECK(strtol("0x2a", NULL, 16) == 42L);
    CHECK(strtol("0x2a", NULL, 0) == 42L);
    CHECK(strtol("052", NULL, 0) == 42L);
    CHECK(strtol("   -42xyz", &end_pointer, 10) == -42L);
    CHECK(end_pointer != NULL && *end_pointer == 'x');
    CHECK(strtol("999999999999999999999999", NULL, 10) == LONG_MAX);
    return 0;
}
