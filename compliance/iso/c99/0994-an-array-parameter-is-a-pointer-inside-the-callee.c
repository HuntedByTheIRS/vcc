/* 0994: CHECK(sizeof parameter == sizeof(void *));
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

static int measure(int parameter[10])
{
    /* 6.7.5.3 adjusts the array to a pointer, so sizeof answers the size of the
     * pointer rather than the size of ten ints. */
    return (int)sizeof parameter;
}

int main(void)
{
    int argument[10];
    CHECK(sizeof argument == 10 * sizeof(int));
    CHECK(measure(argument) == sizeof(void *));
    return 0;
}
