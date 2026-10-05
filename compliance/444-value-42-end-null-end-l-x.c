/* 444: CHECK(value == 42 && end != NULL && *end == L'x');
 *
 * monolithic.c:10970 (characters)
 */

#include <stdio.h>
#include <inttypes.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
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
    wchar_t wide_letters[] = L"abcXYZ123 \t.,;";
    CHECK(wcslen(wide_letters) == 14);
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
            wchar_t wbuf[] = L"abc";
            const wchar_t *wptr = L"xyz";
            CHECK(wc == 65 && sizeof(wc) == sizeof(wchar_t));
            CHECK(sizeof wbuf == 4 * sizeof(wchar_t));
            CHECK(wbuf[0] == L'a' && wbuf[3] == L'\0');
            CHECK(wptr[2] == L'z' && *wptr == L'x');
            CHECK(L'\n' == (wchar_t)10 && L'\t' == (wchar_t)9);
        }
    CHECK(wcslen(L"hello") == 5 && wcslen(L"") == 0);
    CHECK(wcscmp(L"abc", L"abc") == 0);
    CHECK(wcscmp(L"abc", L"abd") < 0 && wcscmp(L"abd", L"abc") > 0);
    CHECK(wcschr(L"abc", L'b') != NULL && *wcschr(L"abc", L'b') == L'b');
    CHECK(wcsstr(L"hello world", L"world") != NULL);
    CHECK(wcsstr(L"hello", L"xyz") == NULL);
    {
            wchar_t dest[16];
            wcscpy(dest, L"copy");
            CHECK(wcscmp(dest, L"copy") == 0);
            wcscat(dest, L"2");
            CHECK(wcscmp(dest, L"copy2") == 0);
            CHECK(swprintf(dest, 16, L"%ls-%d", L"n", 5) == 3);
            CHECK(wcscmp(dest, L"n-5") == 0);
        }
    CHECK(wcstod(L"2.5", NULL) == 2.5);
    CHECK(wcstoll(L"123", NULL, 10) == 123LL);
    CHECK(wcstoull(L"123", NULL, 10) == 123ULL);
    CHECK(wcstoimax(L"-9", NULL, 10) == -9);
    {
    wchar_t *end = NULL;
    long value = wcstol(L"42xyz", &end, 10);
    CHECK(value == 42 && end != NULL && *end == L'x');
    }
    return 0;
}
