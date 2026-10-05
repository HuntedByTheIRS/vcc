/* 937: CHECK(C99_SELF == 1);
 *
 * not in monolithic.c: added after the corpus was split, so it has no line there.
 */

#include <stdio.h>

#define C99_SELF C99_SELF

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int C99_SELF = 1;

int main(void)
{
    CHECK(C99_SELF == 1);
    return 0;
}
