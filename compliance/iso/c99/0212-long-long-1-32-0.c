/* 0212: CHECK(((long long)1 << 32) > 0);
 *
 * monolithic.c:9971 (expressions)
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
    CHECK(((long long)1 << 32) > 0);
    return 0;
}
