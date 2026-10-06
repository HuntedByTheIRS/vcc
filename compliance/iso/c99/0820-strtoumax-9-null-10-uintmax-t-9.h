/* 0820: CHECK(strtoumax("9", NULL, 10) == (uintmax_t)9);
 *
 * monolithic.c:11805 (utilities)
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
    CHECK(strtoumax("9", NULL, 10) == (uintmax_t)9);
    return 0;
}
