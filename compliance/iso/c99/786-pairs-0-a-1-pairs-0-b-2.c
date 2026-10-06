/* 786: CHECK(pairs[0].a == 1 && pairs[0].b == 2);
 *
 * monolithic.c:11743 (utilities)
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

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    c99_pair_t pairs[4] = {{2, 9}, {1, 2}, {2, 3}, {1, 5}};
    qsort(pairs, 4, sizeof pairs[0], c99_compare_pairs);
    CHECK(pairs[0].a == 1 && pairs[0].b == 2);
    return 0;
}
