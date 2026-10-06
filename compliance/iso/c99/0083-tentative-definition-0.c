/* 0083: CHECK(c99_tentative_definition == 0);
 *
 * monolithic.c:9652 (declarations)
 */

#include <stdio.h>

static int c99_tentative_definition;

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(c99_tentative_definition == 0);
    return 0;
}
