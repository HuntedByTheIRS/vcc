/* 0413: CHECK(iswpunct(L'.') && iswcntrl(L'\t') && iswprint(L' ') && iswgraph(L'!'));
 *
 * monolithic.c:10907 (characters)
 */

#include <stdio.h>
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
    CHECK(iswalpha(L'a') && iswalpha(L'Z') && !iswalpha(L'1'));
    CHECK(iswdigit(L'7') && iswspace(L' ') && iswspace(L'\t'));
    CHECK(iswupper(L'A') && iswlower(L'a'));
    CHECK(iswblank(L' ') && iswblank(L'\t') && !iswblank(L'\n'));
    CHECK(iswpunct(L'.') && iswcntrl(L'\t') && iswprint(L' ') && iswgraph(L'!'));
    return 0;
}
