/* 0323: CHECK(sizeof flat_designated == 3 * sizeof(int));
 *
 * monolithic.c:10630 (arrays)
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
    int flat_designated[] = {[0] = 1, [1] = 2, [2] = 3};
    CHECK(sizeof flat_designated == 3 * sizeof(int));
    return 0;
}
