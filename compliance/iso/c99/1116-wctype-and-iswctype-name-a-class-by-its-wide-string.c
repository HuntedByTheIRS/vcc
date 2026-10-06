/* 1116: wctype-and-iswctype-name-a-class-by-its-wide-string
 *
 * ISO/IEC 9899:1999 7.25.2.2.1: the wctype function constructs a value with
 * type wctype_t that describes a class of wide characters.
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
    wctype_t alpha = wctype("alpha");
    wctrans_t lower = wctrans("tolower");
    CHECK(alpha != 0);
    CHECK(iswctype(L'a', alpha) != 0);
    CHECK(!iswctype(L'1', alpha));
    CHECK(lower != 0);
    CHECK(towctrans(L'A', lower) == L'a');
    return 0;
}
