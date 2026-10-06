/* 0034: CHECK(c99_hex_float == 12.0L);
 *
 * monolithic.c:293 (lexical)
 */

#include <stdio.h>

static const long double c99_hex_float = 0x1.8p+3L;

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(c99_hex_float == 12.0L);
    return 0;
}
