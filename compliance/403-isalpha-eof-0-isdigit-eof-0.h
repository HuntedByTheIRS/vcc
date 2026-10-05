/* 403: CHECK(isalpha(EOF) == 0 && isdigit(EOF) == 0);
 *
 * monolithic.c:10873 (characters)
 */

#include <stdio.h>
#include <ctype.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(isalpha('a') && isalpha('Z') && !isalpha('1'));
    CHECK(isdigit('7') && !isdigit('a'));
    CHECK(isalpha(EOF) == 0 && isdigit(EOF) == 0);
    return 0;
}
