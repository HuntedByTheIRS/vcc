/* 792: CHECK(dq.quot == 3 && dq.rem == 2);
 *
 * monolithic.c:11760 (utilities)
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
    div_t dq = div(17, 5);
    CHECK(dq.quot == 3 && dq.rem == 2);
    }
    return 0;
}
