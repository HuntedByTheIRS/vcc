/* 0062: CHECK(c99_large_object[39999] == 0x5A);
 *
 * monolithic.c:9570 (limits)
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
    c99_large_object[39999] = 0x5A;
    CHECK(c99_large_object[39999] == 0x5A);
    return 0;
}
