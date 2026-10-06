/* 0402: CHECK(tolower('1') == '1' && toupper('1') == '1');
 *
 * monolithic.c:10872 (characters)
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
    CHECK(tolower('A') == 'a' && toupper('a') == 'A');
    CHECK(tolower('1') == '1' && toupper('1') == '1');
    return 0;
}
