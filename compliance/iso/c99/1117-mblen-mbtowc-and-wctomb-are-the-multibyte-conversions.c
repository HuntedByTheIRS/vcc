/* 1117: mblen-mbtowc-and-wctomb-are-the-multibyte-conversions
 *
 * ISO/IEC 9899:1999 7.20.7: 7.20.7.1p1 the mblen function determines the
 * number of bytes contained in a multibyte character.
 */

#include <stdlib.h>
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
    wchar_t wc = 0;
    char buf[8];
    size_t n;
    memset(&wc, 0, sizeof wc);
    memset(buf, 0, sizeof buf);
    CHECK(mblen("a", 1) == 1);
    CHECK(mbtowc(&wc, "a", 1) == 1 && wc == L'a');
    CHECK(wctomb(buf, L'a') == 1 && buf[0] == 'a');
    n = mbstowcs(&wc, "a", 1);
    CHECK(n == 1 && wc == L'a');
    CHECK(wcstombs(buf, L"a", sizeof buf) == 1 && buf[0] == 'a');
    return 0;
}
