/* 0425: CHECK(wc == 65 && sizeof(wc) == sizeof(wchar_t));
 *
 * monolithic.c:10938 (characters)
 */

#include <stdio.h>
#include <stdarg.h>
#include <stddef.h>
#include <wchar.h>
#include <wctype.h>

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
    CHECK(iswalpha(L'a') && iswalpha(L'Z') && !iswalpha(L'1'));
    CHECK(iswdigit(L'7') && iswspace(L' ') && iswspace(L'\t'));
    CHECK(iswupper(L'A') && iswlower(L'a'));
    CHECK(iswblank(L' ') && iswblank(L'\t') && !iswblank(L'\n'));
    CHECK(iswpunct(L'.') && iswcntrl(L'\t') && iswprint(L' ') && iswgraph(L'!'));
    CHECK(iswxdigit(L'f') && iswxdigit(L'9'));
    CHECK(towlower(L'A') == L'a' && towupper(L'a') == L'A');
    CHECK(towlower(L'a') == L'a' && towupper(L'A') == L'A');
    {
            wctype_t alpha_class = wctype("alpha");
            wctype_t digit_class = wctype("digit");
            wctrans_t lower_map = wctrans("tolower");
            wctrans_t upper_map = wctrans("toupper");
            CHECK(alpha_class != (wctype_t)0);
            CHECK(digit_class != (wctype_t)0);
            CHECK(iswctype(L'a', alpha_class) != 0);
            CHECK(iswctype(L'1', digit_class) != 0);
            CHECK(iswctype(L'1', alpha_class) == 0);
            if (lower_map != (wctrans_t)0) {
                CHECK(towctrans(L'A', lower_map) == L'a');
            }
            if (upper_map != (wctrans_t)0) {
                CHECK(towctrans(L'a', upper_map) == L'A');
            }
            CHECK(towctrans(L'1', lower_map) == L'1');
        }
    {
    wchar_t wc = L'A';
    CHECK(wc == 65 && sizeof(wc) == sizeof(wchar_t));
    }
    return 0;
}
