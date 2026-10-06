/* 793: CHECK(ldq.quot == 3L && ldq.rem == 2L);
 *
 * monolithic.c:11761 (utilities)
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
    ldiv_t ldq = ldiv(17L, 5L);
    CHECK(ldq.quot == 3L && ldq.rem == 2L);
    }
    return 0;
}
