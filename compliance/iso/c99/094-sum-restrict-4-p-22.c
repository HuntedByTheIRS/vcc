/* 094: CHECK(c99_sum_restrict(4, p) == 22);
 *
 * monolithic.c:9670 (declarations)
 */

#include <stdio.h>

typedef int *c99_intptr_t;

static int c99_sum_restrict(int n, c99_intptr_t restrict p)
{
    int total = 0;
    for (int i = 0; i < n; ++i) {
        total += p[i];
    }
    return total;
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
    int i = 0;
    c99_intptr_t p;
    int numbers[4] = {4, 5, 6, 7};
    for (int loop_var = 0; loop_var < 3; ++loop_var) { /* C99 for-decl */
            i += loop_var;
        }
    CHECK(i == 3);
    p = numbers;
    CHECK(c99_sum_restrict(4, p) == 22);
    return 0;
}
