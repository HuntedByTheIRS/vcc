/* 411: CHECK(iswupper(L'A') && iswlower(L'a'));
 *
 * monolithic.c:10905 (characters)
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
    return 0;
}
