/* 032: CHECK(c99_ll_max == LLONG_MAX);
 *
 * monolithic.c:291 (lexical)
 */

#include <stdio.h>
#include <limits.h>

static const long long c99_ll_max = 9223372036854775807LL;

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(c99_ll_max == LLONG_MAX);
    return 0;
}
