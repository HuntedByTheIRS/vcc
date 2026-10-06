/* 0012: CHECK(C99_COUNT(9, 8, 7, 6) == 4);
 *
 * monolithic.c:233 (preprocessor)
 */

#include <stdio.h>

#define C99_NARGS(_1, _2, _3, _4, _5, N, ...) N

#define C99_COUNT(...) C99_NARGS(__VA_ARGS__, 5, 4, 3, 2, 1, 0)

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(C99_COUNT(9) == 1);
    CHECK(C99_COUNT(9, 8, 7, 6) == 4);
    return 0;
}
