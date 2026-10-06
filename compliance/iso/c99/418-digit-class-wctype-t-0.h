/* 418: CHECK(digit_class != (wctype_t)0);
 *
 * monolithic.c:10920 (characters)
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
    {
    wctype_t alpha_class = wctype("alpha");
    wctype_t digit_class = wctype("digit");
    CHECK(alpha_class != (wctype_t)0);
    CHECK(digit_class != (wctype_t)0);
    }
    return 0;
}
