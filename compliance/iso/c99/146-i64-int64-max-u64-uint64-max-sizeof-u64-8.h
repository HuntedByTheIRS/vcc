/* 146: CHECK(i64 == INT64_MAX && u64 == UINT64_MAX && sizeof(u64) == 8);
 *
 * monolithic.c:9826 (types)
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
    int64_t i64 = INT64_MAX;
    uint64_t u64 = UINT64_MAX;
    CHECK(i64 == INT64_MAX && u64 == UINT64_MAX && sizeof(u64) == 8);
    return 0;
}
