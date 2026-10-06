/* 153: CHECK(INT64_C(1) == 1 && UINT64_C(1) == 1ull);
 *
 * monolithic.c:9833 (types)
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
    CHECK(INT64_C(1) == 1 && UINT64_C(1) == 1ull);
    return 0;
}
