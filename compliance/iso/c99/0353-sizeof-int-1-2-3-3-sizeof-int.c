/* 0353: CHECK(sizeof (int[]){1, 2, 3} == 3 * sizeof(int));
 *
 * monolithic.c:10699 (arrays)
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
    CHECK(sizeof (int[]){1, 2, 3} == 3 * sizeof(int));
    }
    return 0;
}
