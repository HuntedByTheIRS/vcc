/* 819: CHECK(strtoimax("-9", NULL, 10) == (intmax_t)-9);
 *
 * monolithic.c:11804 (utilities)
 */

#include <stdio.h>
#include <inttypes.h>
#include <stddef.h>
#include <stdint.h>
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
            div_t dq = div(17, 5);
            ldiv_t ldq = ldiv(17L, 5L);
            lldiv_t lldq = lldiv(17LL, 5LL);
            imaxdiv_t idq = imaxdiv((intmax_t)17, (intmax_t)5);
            CHECK(dq.quot == 3 && dq.rem == 2);
            CHECK(ldq.quot == 3L && ldq.rem == 2L);
            CHECK(lldq.quot == 3LL && lldq.rem == 2LL);
            CHECK(idq.quot == 3 && idq.rem == 2);
            CHECK(imaxabs((intmax_t)-5) == 5);
        }
    CHECK(strtoimax("-9", NULL, 10) == (intmax_t)-9);
    return 0;
}
