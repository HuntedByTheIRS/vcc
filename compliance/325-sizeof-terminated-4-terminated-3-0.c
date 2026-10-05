/* 325: CHECK(sizeof terminated == 4 && terminated[3] == '\0');
 *
 * monolithic.c:10632 (arrays)
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
    char terminated[4] = "abc";
    CHECK(sizeof terminated == 4 && terminated[3] == '\0');
    return 0;
}
