/* 001: CHECK(C99_FN_MACRO(1, 2) == 1002);
 *
 * monolithic.c:216 (preprocessor)
 */

#include <stdio.h>

#define C99_FN_MACRO(a, b) ((a) * 1000 + (b))

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(C99_FN_MACRO(1, 2) == 1002);
    return 0;
}
