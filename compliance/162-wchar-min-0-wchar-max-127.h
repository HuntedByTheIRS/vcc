/* 162: CHECK(WCHAR_MIN <= 0 && WCHAR_MAX > 127);
 *
 * monolithic.c:9852 (types)
 */

#include <stdio.h>
#include <stdint.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(WCHAR_MIN <= 0 && WCHAR_MAX > 127);
    return 0;
}
