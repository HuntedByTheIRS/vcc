/* 0452: CHECK(MB_CUR_MAX >= 1 && MB_LEN_MAX >= MB_CUR_MAX);
 *
 * monolithic.c:10991 (characters)
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
    {
    CHECK(MB_CUR_MAX >= 1 && MB_LEN_MAX >= MB_CUR_MAX);
    }
    return 0;
}
