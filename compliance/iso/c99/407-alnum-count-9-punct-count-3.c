/* 407: CHECK(alnum_count == 9 && punct_count == 3);
 *
 * monolithic.c:10898 (characters)
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
    const char *letters = "abcXYZ123 \t.,;";
    CHECK(isalnum('a') && isalnum('7') && !isalnum(' '));
    CHECK(ispunct('.') && ispunct(',') && !ispunct('a'));
    {
    const char *scan = letters;
    int alnum_count = 0, punct_count = 0;
    while (*scan != '\0') {
                if (isalnum((unsigned char)*scan)) {
                    ++alnum_count;
                } else if (ispunct((unsigned char)*scan)) {
                    ++punct_count;
                }
                ++scan;
            }
    CHECK(alnum_count == 9 && punct_count == 3);
    }
    return 0;
}
