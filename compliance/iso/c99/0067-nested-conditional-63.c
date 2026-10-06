/* 0067: CHECK(c99_nested_conditional() == 63);
 *
 * monolithic.c:9575 (limits)
 */

#include <stdio.h>

static int c99_nested_conditional(void)
{
    int n = 0;
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#if 1
#define C99_PP_NESTING_LEVEL 63
    n = C99_PP_NESTING_LEVEL;
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
    return n;
}

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(c99_nested_conditional() == 63);
    return 0;
}
