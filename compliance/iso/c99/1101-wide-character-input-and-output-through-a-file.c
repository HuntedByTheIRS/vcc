/* 1101: wide-character-input-and-output-through-a-file
 *
 * ISO/IEC 9899:1999 7.24.3.1: 7.24.3.1p1 the fgetwc function reads a single
 * wide character from the input stream pointed to by stream.
 */

#include <stdio.h>
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
    FILE *f = tmpfile();
    wint_t c;
    if (!f)
        return 1;
    CHECK(fputwc(L'x', f) == L'x');
    CHECK(fputws(L"yz", f) >= 0);
    rewind(f);
    c = fgetwc(f);
    CHECK(c == L'x');
    ungetwc(c, f);
    CHECK(fgetwc(f) == L'x');
    fclose(f);
    return 0;
}
