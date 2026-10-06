/* 1103: getwc-putwc-and-getwchar-are-the-wide-single-character-macros
 *
 * ISO/IEC 9899:1999 7.24.3.5: the getwc function is equivalent to fgetwc
 * and the putwc function to fputwc.
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
    if (!f)
        return 1;
    CHECK(putwc(L'a', f) == L'a');
    rewind(f);
    CHECK(getwc(f) == L'a');
    fclose(f);
    return 0;
}
