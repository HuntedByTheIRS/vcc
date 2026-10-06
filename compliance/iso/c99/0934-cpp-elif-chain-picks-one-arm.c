/* 0934: CHECK(C99_ARM == 2);
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

#if 0
#define C99_ARM 0
#elif 1
#define C99_ARM 2
#else
#define C99_ARM 3
#endif

int main(void)
{
    CHECK(C99_ARM == 2);
    return 0;
}
