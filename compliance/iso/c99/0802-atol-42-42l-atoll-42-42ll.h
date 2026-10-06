/* 0802: CHECK(atol("42") == 42L && atoll("42") == 42LL);
 *
 * monolithic.c:11787 (utilities)
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
    CHECK(atol("42") == 42L && atoll("42") == 42LL);
    return 0;
}
