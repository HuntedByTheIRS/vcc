/* 0709: CHECK(sscanf("42 -7 word 3.5", "%d %d %15s", &int_a, &int_b, word) == 3);
 *
 * monolithic.c:11527 (stdio)
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    char word[16];
    int int_a = 0, int_b = 0;
    CHECK(sscanf("42 -7 word 3.5", "%d %d %15s", &int_a, &int_b, word) == 3);
    return 0;
}
