/* 794: CHECK(lldq.quot == 3LL && lldq.rem == 2LL);
 *
 * monolithic.c:11762 (utilities)
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
    {
    lldiv_t lldq = lldiv(17LL, 5LL);
    CHECK(lldq.quot == 3LL && lldq.rem == 2LL);
    }
    return 0;
}
