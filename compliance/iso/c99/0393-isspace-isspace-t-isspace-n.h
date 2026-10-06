/* 0393: CHECK(isspace(' ') && isspace('\t') && isspace('\n'));
 *
 * monolithic.c:10863 (characters)
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
    CHECK(isspace(' ') && isspace('\t') && isspace('\n'));
    return 0;
}
