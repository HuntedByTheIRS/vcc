/* 790: CHECK(found != NULL && found->a == 2 && found->b == 3);
 *
 * monolithic.c:11750 (utilities)
 */

#include <stdio.h>
#include <stddef.h>
#include <stdlib.h>

typedef struct c99_pair { int a, b; } c99_pair_t;

static int c99_compare_pairs(const void *lhs, const void *rhs)
{
    const c99_pair_t *a = lhs;
    const c99_pair_t *b = rhs;

    if (a->a != b->a) {
        return a->a < b->a ? -1 : 1;
    }
    if (a->b != b->b) {
        return a->b < b->b ? -1 : 1;
    }
    return 0;
}

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
    c99_pair_t pairs[4] = {{2, 9}, {1, 2}, {2, 3}, {1, 5}};
    qsort(sorted, 7, sizeof sorted[0], c99_compare_ints);
    CHECK(sorted[0] == 1 && sorted[3] == 4 && sorted[6] == 7);
    {
            int key = 5;
            int *found = bsearch(&key, sorted, 7, sizeof sorted[0], c99_compare_ints);
            CHECK(found != NULL && *found == 5);
            key = 100;
            CHECK(bsearch(&key, sorted, 7, sizeof sorted[0], c99_compare_ints) == NULL);
        }
    qsort(pairs, 4, sizeof pairs[0], c99_compare_pairs);
    CHECK(pairs[0].a == 1 && pairs[0].b == 2);
    CHECK(pairs[1].a == 1 && pairs[1].b == 5);
    CHECK(pairs[2].a == 2 && pairs[2].b == 3);
    CHECK(pairs[3].a == 2 && pairs[3].b == 9);
    {
    c99_pair_t key = {2, 3};
    c99_pair_t *found = bsearch(&key, pairs, 4, sizeof pairs[0], c99_compare_pairs);
    CHECK(found != NULL && found->a == 2 && found->b == 3);
    }
    return 0;
}
