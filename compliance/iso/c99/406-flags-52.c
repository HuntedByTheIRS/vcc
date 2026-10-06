/* 406: CHECK(flags == 52);
 *
 * monolithic.c:10883 (characters)
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
    {
    int flags = 0;
    for (int c = 0; c < 256; ++c) {
                flags += isalpha(c) != 0;
            }
    CHECK(flags == 52);
    }
    return 0;
}
