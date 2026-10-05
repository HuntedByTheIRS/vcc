/* 037: CHECK(c99_float_suffix == 3.5f);
 *
 * monolithic.c:296 (lexical)
 */

#include <stdio.h>

static const float c99_float_suffix = 3.5f;

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(c99_float_suffix == 3.5f);
    return 0;
}
