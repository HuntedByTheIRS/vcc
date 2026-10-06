/* 0814: CHECK(strtoll("-9223372036854775807", NULL, 10) == LLONG_MIN + 1);
 *
 * monolithic.c:11799 (utilities)
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
    CHECK(strtoll("-9223372036854775807", NULL, 10) == LLONG_MIN + 1);
    return 0;
}
