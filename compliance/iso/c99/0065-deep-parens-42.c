/* 0065: CHECK(c99_deep_parens() == 42);
 *
 * monolithic.c:9573 (limits)
 */

#include <stdio.h>

static int c99_deep_parens(void)
{
    int v = (((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((42)))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))));
    return v;
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
    CHECK(c99_deep_parens() == 42);
    return 0;
}
