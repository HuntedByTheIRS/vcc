/* 0935: CHECK(C99_SPLIT(1, 2) == 3);
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

#define C99_SUM(a, b) ((a) + (b))

int main(void)
{
    CHECK(C99_SUM(1,
                  2) == 3);
    return 0;
}
