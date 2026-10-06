/* 1115: the-wide-classification-functions-answer-for-wide-characters
 *
 * ISO/IEC 9899:1999 7.25.2.1.1: the iswalnum function tests for any wide
 * character for which isalnum is true.
 */

#include <wctype.h>

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
    CHECK(iswalnum(L'a') && iswalnum(L'1') && !iswalnum(L' '));
    CHECK(iswalpha(L'a') && !iswalpha(L'1'));
    CHECK(iswblank(L' ') && !iswblank(L'a'));
    CHECK(iswcntrl(L'\n') && !iswcntrl(L'a'));
    CHECK(iswdigit(L'1') && !iswdigit(L'a'));
    CHECK(iswgraph(L'a') && !iswgraph(L'\n'));
    CHECK(iswlower(L'a') && !iswlower(L'A'));
    CHECK(iswprint(L'a') && !iswprint(L'\n'));
    CHECK(iswpunct(L',') && !iswpunct(L'a'));
    CHECK(iswspace(L' ') && !iswspace(L'a'));
    CHECK(iswupper(L'A') && !iswupper(L'a'));
    CHECK(iswxdigit(L'f') && !iswxdigit(L'g'));
    CHECK(towlower(L'A') == L'a');
    CHECK(towupper(L'a') == L'A');
    return 0;
}
