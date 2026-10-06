/* 396: CHECK(isxdigit('f') && isxdigit('F') && isxdigit('9') && !isxdigit('g'));
 *
 * monolithic.c:10866 (characters)
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
    CHECK(isxdigit('f') && isxdigit('F') && isxdigit('9') && !isxdigit('g'));
    return 0;
}
