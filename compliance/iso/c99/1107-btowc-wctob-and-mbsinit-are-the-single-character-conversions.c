/* 1107: btowc-wctob-and-mbsinit-are-the-single-character-conversions
 *
 * ISO/IEC 9899:1999 7.24.6.1.1: the btowc function determines whether c
 * constitutes a valid single-byte character in the initial shift state.
 */

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
    wchar_t wc = 0;
    int i;
    for (i = 0; i < (int)sizeof st; i++)
        ((char *)&st)[i] = 0;
    CHECK(btowc('a') == L'a');
    CHECK(wctob(L'a') == 'a');
    CHECK(mbsinit(&st) != 0);
    CHECK(wcrtomb((char *)&wc, L'a', &st) == 1);
    return 0;
}
