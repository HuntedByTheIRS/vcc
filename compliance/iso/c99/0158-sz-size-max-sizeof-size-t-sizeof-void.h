/* 0158: CHECK(sz == SIZE_MAX && sizeof(size_t) == sizeof(void *));
 *
 * monolithic.c:9848 (types)
 */

#include <stdio.h>
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
    size_t sz = SIZE_MAX;
    CHECK(sz == SIZE_MAX && sizeof(size_t) == sizeof(void *));
    return 0;
}
