/* 318: CHECK(sizeof deduced == 5 * sizeof(int) && deduced[4] == 11);
 *
 * monolithic.c:10625 (arrays)
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
    int deduced[] = {2, 3, 5, 7, 11};
    CHECK(sizeof deduced == 5 * sizeof(int) && deduced[4] == 11);
    return 0;
}
