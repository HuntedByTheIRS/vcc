/* 830: CHECK(atexit(c99_remember_atexit) == 0);
 *
 * monolithic.c:11831 (utilities)
 */

#include <stdio.h>
#include <stddef.h>
#include <stdlib.h>

static int c99_atexit_runs;

static void c99_remember_atexit(void)
{
    ++c99_atexit_runs;
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
    CHECK(atexit(c99_remember_atexit) == 0);
    return 0;
}
