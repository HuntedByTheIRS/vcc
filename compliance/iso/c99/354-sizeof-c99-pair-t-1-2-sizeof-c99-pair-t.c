/* 354: CHECK(sizeof (c99_pair_t){1, 2} == sizeof(c99_pair_t));
 *
 * monolithic.c:10700 (arrays)
 */

#include <stdio.h>

typedef struct c99_pair { int a, b; } c99_pair_t;

static int c99_pair_sum(c99_pair_t p);

static int c99_pair_sum(c99_pair_t p)
{
    return p.a + p.b;
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
    {
    c99_pair_t *pr = &(c99_pair_t){3, 4}
    ;
    CHECK(pr->a == 3 && pr->b == 4);
    pr->a = 5;
    CHECK(pr->a == 5);
    CHECK(c99_pair_sum((c99_pair_t){1, 1}) == 2);
    CHECK(sizeof (c99_pair_t){1, 2} == sizeof(c99_pair_t));
    }
    return 0;
}
