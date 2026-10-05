/* 035: CHECK(c99_hex_float2 == 1.0);
 *
 * monolithic.c:294 (lexical)
 */

#include <stdio.h>

static const double c99_hex_float2 = 0x.8p1;

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(c99_hex_float2 == 1.0);
    return 0;
}
