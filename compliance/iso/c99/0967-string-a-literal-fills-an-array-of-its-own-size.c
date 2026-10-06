/* 0967: CHECK(sizeof word == 4 && word[3] == 0);
 *
 * not in monolithic.c: added after the corpus was split, so it has no line there.
 */

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
    /* An array initialized by a string literal is one element longer than the
     * characters in it, and that element is the zero. */
    char word[] = "abc";
    CHECK(sizeof word == 4);
    CHECK(word[0] == 'a' && word[2] == 'c');
    CHECK(word[3] == 0);
    return 0;
}
