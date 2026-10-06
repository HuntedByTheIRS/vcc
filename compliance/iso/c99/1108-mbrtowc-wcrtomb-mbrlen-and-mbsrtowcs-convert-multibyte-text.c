/* 1108: mbrtowc-wcrtomb-mbrlen-and-mbsrtowcs-convert-multibyte-text
 *
 * ISO/IEC 9899:1999 7.24.6.3.2: the mbrtowc function converts a multibyte
 * sequence to a wide character.
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
    mbstate_t st;
    char buf[8];
    wchar_t wc = 0;
    wchar_t out[8];
    const char *src = "ab";
    memset(&st, 0, sizeof st);
    CHECK(mbrtowc(&wc, "a", 1, &st) == 1 && wc == L'a');
    CHECK(mbrlen("a", 1, NULL) == 1);
    CHECK(wcrtomb(buf, L'a', &st) == 1 && buf[0] == 'a');
    CHECK(mbsrtowcs(out, &src, 8, &st) == 2);
    CHECK(out[0] == L'a' && out[1] == L'b');
    return 0;
}
