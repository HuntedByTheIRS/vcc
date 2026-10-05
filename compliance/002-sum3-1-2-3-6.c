/* 002: CHECK(C99_SUM3(1, 2, 3) == 6);
 *
 * monolithic.c:217 (preprocessor)
 */

#include <stdio.h>

#define C99_SUM3(a, b, c) ((a) + (b) + (c))

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(C99_SUM3(1, 2, 3) == 6);
    return 0;
}
