/* 0085: CHECK(c99_volatile_object == 2);
 *
 * monolithic.c:9655 (declarations)
 */

#include <stdio.h>

static volatile int c99_volatile_object = 1;

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    c99_volatile_object = 2;
    CHECK(c99_volatile_object == 2);
    return 0;
}
