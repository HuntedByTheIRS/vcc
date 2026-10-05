/* 796: CHECK(imaxabs((intmax_t)-5) == 5);
 *
 * monolithic.c:11764 (utilities)
 */

#include <stdio.h>
#include <inttypes.h>
#include <stddef.h>
#include <stdint.h>

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
    imaxdiv_t idq = imaxdiv((intmax_t)17, (intmax_t)5);
    CHECK(idq.quot == 3 && idq.rem == 2);
    CHECK(imaxabs((intmax_t)-5) == 5);
    }
    return 0;
}
