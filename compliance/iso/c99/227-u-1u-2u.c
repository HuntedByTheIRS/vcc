/* 227: CHECK(u + 1u == 2u);
 *
 * monolithic.c:9998 (expressions)
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
    unsigned int u = 1u;
    CHECK(u + 1u == 2u);
    return 0;
}
