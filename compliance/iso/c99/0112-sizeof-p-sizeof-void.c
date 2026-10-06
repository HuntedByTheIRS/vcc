/* 0112: CHECK(sizeof p == sizeof(void *));
 *
 * monolithic.c:9724 (declarations)
 */

#include <stdio.h>

static int c99_file_scope_object = 100;

extern int c99_file_scope_object;

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
    int before = c99_file_scope_object;
    before += 1;
    long after = before * 2L;
    int i = 0;
    c99_intptr_t p;
    int numbers[4] = {4, 5, 6, 7};
    for (int loop_var = 0; loop_var < 3; ++loop_var) { /* C99 for-decl */
            i += loop_var;
        }
    CHECK(i == 3);
    CHECK(before == 101 && after == 202L);
    CHECK(c99_file_scope_object == 100);
    p = numbers;
    CHECK(c99_sum_restrict(4, p) == 22);
    CHECK(p[3] == 7 && *(p + 3) == 7 && 3[p] == 7);
    {                                  /* nested block scope */
            int before = 1000;             /* shadows the outer object */
            CHECK(before == 1000);
            CHECK(c99_file_scope_object == 100);
            {
                int before = 2000;         /* shadow again, two levels deep */
                CHECK(before == 2000 && i == 3);
            }
        }
    CHECK(before == 101);
    {                                  /* storage-class specifiers */
            auto int auto_var = 3;         /* auto: no effect, still valid */
            static int static_local = 0;
            extern int c99_file_scope_object;   /* redundant extern declaration */
            ++static_local;
            CHECK(auto_var == 3);
            CHECK(static_local == 1);
            CHECK(c99_file_scope_object == 100);
        }
    {
            int n = 3;
            typedef int c99_vla_t[n];
            c99_vla_t vla;         /* no initializer is allowed for a VLA */
            vla[0] = 1;
            vla[1] = 2;
            vla[2] = 3;
            CHECK(sizeof(c99_vla_t) == 3 * sizeof(int));
            CHECK(sizeof vla == sizeof(c99_vla_t));
            CHECK(vla[0] + vla[1] + vla[2] == 6);
        }
    CHECK(sizeof(int) == sizeof i);
    CHECK(sizeof numbers == 4 * sizeof(int));
    CHECK(sizeof p == sizeof(void *));
    return 0;
}
