/* 408: CHECK(sizeof(wchar_t) >= 2 && WEOF == (wint_t)-1);
 *
 * monolithic.c:10902 (characters)
 */

#include <stdio.h>
#include <stdarg.h>
#include <stddef.h>
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
    CHECK(sizeof(wchar_t) >= 2 && WEOF == (wint_t)-1);
    return 0;
}
