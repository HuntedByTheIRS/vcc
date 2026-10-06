/* 0939: CHECK(C99_ALIAS == 7);
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

#define C99_TARGET 7
#define C99_ALIAS C99_TARGET

int main(void)
{
    CHECK(C99_ALIAS == 7);
    return 0;
}
