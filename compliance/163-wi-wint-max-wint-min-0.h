/* 163: CHECK(wi == WINT_MAX && WINT_MIN <= 0);
 *
 * monolithic.c:9853 (types)
 */

#include <stdio.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <wchar.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    wint_t wi = WINT_MAX;
    CHECK(wi == WINT_MAX && WINT_MIN <= 0);
    return 0;
}
