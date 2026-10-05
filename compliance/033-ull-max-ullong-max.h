/* 033: CHECK(c99_ull_max == ULLONG_MAX);
 *
 * monolithic.c:292 (lexical)
 */

#include <stdio.h>
#include <limits.h>

static const unsigned long long c99_ull_max = 18446744073709551615ULL;

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(c99_ull_max == ULLONG_MAX);
    return 0;
}
