/* 457: CHECK(fwide(wf, 1) > 0);
 *
 * monolithic.c:11013 (characters)
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
    {
    FILE *wf = tmpfile();
    if (wf != NULL) {
    CHECK(fwide(wf, 0) == 0);
    CHECK(fwide(wf, 1) > 0);
        }
    }
    return 0;
}
