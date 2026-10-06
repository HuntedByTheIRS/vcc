/* 0126: CHECK(uc == 255u && sc == -128 && sizeof(char) == 1);
 *
 * monolithic.c:9804 (types)
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
    unsigned char uc = 255;
    signed char sc = -128;
    CHECK(uc == 255u && sc == -128 && sizeof(char) == 1);
    return 0;
}
