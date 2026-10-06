/* 791: CHECK(abs(-5) == 5 && labs(-5L) == 5L && llabs(-5LL) == 5LL);
 *
 * monolithic.c:11754 (utilities)
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
    CHECK(abs(-5) == 5 && labs(-5L) == 5L && llabs(-5LL) == 5LL);
    return 0;
}
