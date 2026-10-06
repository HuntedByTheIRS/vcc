/* 0401: CHECK(tolower('A') == 'a' && toupper('a') == 'A');
 *
 * monolithic.c:10871 (characters)
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
    return 0;
}
