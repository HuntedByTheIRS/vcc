/* 445: CHECK(mbsinit(&state) != 0);
 *
 * monolithic.c:10981 (characters)
 */

#include <stdio.h>
#include <stdarg.h>
#include <stddef.h>
#include <string.h>
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
    {
    mbstate_t state;
    memset(&state, 0, sizeof state);
    CHECK(mbsinit(&state) != 0);
    }
    return 0;
}
