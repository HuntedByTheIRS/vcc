/* 0863: CHECK(ticks >= (clock_t)0);
 *
 * monolithic.c:11990 (runtime)
 */

#include <stdio.h>
#include <stddef.h>
#include <time.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    {
    clock_t ticks = clock();
    CHECK(ticks >= (clock_t)0);
    }
    return 0;
}
