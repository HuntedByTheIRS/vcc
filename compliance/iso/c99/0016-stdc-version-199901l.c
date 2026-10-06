/* 0016: CHECK(__STDC_VERSION__ >= 199901L);
 *
 * monolithic.c:240 (preprocessor)
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
    CHECK(__STDC_VERSION__ >= 199901L);
    return 0;
}
