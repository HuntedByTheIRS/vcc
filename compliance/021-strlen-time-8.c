/* 021: CHECK(strlen(__TIME__) >= 8);
 *
 * monolithic.c:245 (preprocessor)
 */

#include <stdio.h>
#include <stddef.h>
#include <string.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(strlen(__DATE__) >= 11);
    CHECK(strlen(__TIME__) >= 8);
    return 0;
}
