/* 0159: CHECK(pd == PTRDIFF_MAX && sizeof(ptrdiff_t) == sizeof(void *));
 *
 * monolithic.c:9849 (types)
 */

#include <stdio.h>
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
    ptrdiff_t pd = PTRDIFF_MAX;
    CHECK(pd == PTRDIFF_MAX && sizeof(ptrdiff_t) == sizeof(void *));
    return 0;
}
