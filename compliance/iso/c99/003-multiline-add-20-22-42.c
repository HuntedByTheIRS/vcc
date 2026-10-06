/* 003: CHECK(C99_MULTILINE_ADD(20, 22) == 42);
 *
 * monolithic.c:218 (preprocessor)
 */

#include <stdio.h>

#define C99_MULTILINE_ADD(a, b) \
    ((a) +                    \
     (b))

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(C99_MULTILINE_ADD(20, 22) == 42);
    return 0;
}
