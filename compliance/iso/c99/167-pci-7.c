/* 167: CHECK(*pci == 7);
 *
 * monolithic.c:9859 (types)
 */

#include <stdio.h>

static const int c99_const_object = 7;

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    const int *pci = &c99_const_object;
    CHECK(*pci == 7);
    return 0;
}
