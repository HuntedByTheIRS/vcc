/* 061: CHECK(sizeof c99_large_object == 40000);
 *
 * monolithic.c:9568 (limits)
 */

#include <stdio.h>

static unsigned char c99_large_object[40000];

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(sizeof c99_large_object == 40000);
    return 0;
}
