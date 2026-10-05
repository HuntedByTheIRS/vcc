/* 409: CHECK(iswalpha(L'a') && iswalpha(L'Z') && !iswalpha(L'1'));
 *
 * monolithic.c:10903 (characters)
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
    return 0;
}
