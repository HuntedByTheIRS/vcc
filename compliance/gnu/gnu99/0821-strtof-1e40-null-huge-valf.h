/* 0821: CHECK(strtof("1e40", NULL) == HUGE_VALF);
 *
 * monolithic.c:11806 (utilities)
 */

#include <stdio.h>
#include <math.h>
#include <stddef.h>
#include <stdlib.h>
#include <tgmath.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(strtof("2.5", NULL) == 2.5f);
    CHECK(strtof("1e40", NULL) == HUGE_VALF);
    return 0;
}
