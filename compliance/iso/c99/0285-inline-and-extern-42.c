/* 0285: CHECK(c99_inline_and_extern() == 42);
 *
 * monolithic.c:10411 (functions)
 */

#include <stdio.h>

extern inline int c99_inline_and_extern(void)
{
    return 42;
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
    CHECK(c99_inline_and_extern() == 42);
    return 0;
}
