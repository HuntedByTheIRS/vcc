/* 1109: wcsrtombs-converts-a-wide-string-to-multibyte
 *
 * ISO/IEC 9899:1999 7.24.6.4.1: the wcsrtombs function converts a sequence
 * of wide characters to a sequence of multibyte characters.
 */

#include <string.h>
#include <wchar.h>

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    mbstate_t st;
    char buf[8];
    const wchar_t *src = L"ab";
    memset(&st, 0, sizeof st);
    CHECK(wcsrtombs(buf, &src, 8, &st) == 2);
    CHECK(buf[0] == 'a' && buf[1] == 'b' && buf[2] == '\0');
    return 0;
}
