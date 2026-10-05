/* 169: CHECK(vci == 3);
 *
 * monolithic.c:9862 (types)
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
    volatile const int vci = 3;
    CHECK(vci == 3);
    return 0;
}
