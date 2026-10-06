/* 933: CHECK(C99_PROBE == 3);
 *
 * not in monolithic.c: added after the corpus was split, so it has no line there.
 */

#include <stdio.h>

#define C99_PROBE 3

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

#if defined(C99_PROBE) && C99_PROBE == 3
#define C99_BRANCH 1
#define C99_VALUE 30
#else
#define C99_BRANCH 0
#define C99_VALUE 99
#endif

int main(void)
{
    CHECK(C99_BRANCH == 1);
    CHECK(C99_VALUE == 30);
    return 0;
}
