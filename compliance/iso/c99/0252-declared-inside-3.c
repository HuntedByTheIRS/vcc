/* 0252: CHECK(declared_inside == 3);
 *
 * monolithic.c:10115 (control-flow)
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
    {
    int declared_inside = 0;
    for (int k2 = 0; k2 < 3; ++k2) declared_inside += k2;
    CHECK(declared_inside == 3);
    }
    return 0;
}
