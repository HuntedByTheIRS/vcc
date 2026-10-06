/* 0991: CHECK(got == 100);
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

static int file_scope = 100;

int main(void)
{
    int got = -1;
    {
        extern int file_scope;
        got = file_scope;
    }
    CHECK(got == 100);
    return 0;
}
