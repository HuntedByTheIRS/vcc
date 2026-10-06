/* 0784: CHECK(found != NULL && *found == 5);
 *
 * monolithic.c:11738 (utilities)
 */

#include <stdio.h>
#include <stddef.h>
#include <stdlib.h>

static int c99_compare_ints(const void *lhs, const void *rhs)
{
    int a = *(const int *)lhs;
    int b = *(const int *)rhs;

    return (a > b) - (a < b);
}

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    int sorted[7] = {7, 1, 5, 3, 2, 6, 4};
    qsort(sorted, 7, sizeof sorted[0], c99_compare_ints);
    CHECK(sorted[0] == 1 && sorted[3] == 4 && sorted[6] == 7);
    {
    int key = 5;
    int *found = bsearch(&key, sorted, 7, sizeof sorted[0], c99_compare_ints);
    CHECK(found != NULL && *found == 5);
    }
    return 0;
}
