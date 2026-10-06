/* 100: CHECK(sizeof(inner_pair) == 2 * sizeof(long));
 *
 * monolithic.c:9689 (declarations)
 */

#include <stdio.h>

static int g_fail;

static int g_section_checks;

static void sec_begin(const char *title)
{
    if (g_section_checks != 0) {
        printf("    (%d checks)\n", g_section_checks);
    }
    g_section_checks = 0;
    printf("[%s]\n", title);
}

static int c99_file_scope_object = 100;

extern int c99_file_scope_object;

static int c99_tentative_definition;

static const int c99_const_object = 7;

static volatile int c99_volatile_object = 1;

static int c99_static_array[4] = {1, 2};

typedef int c99_array3_t[3];

typedef int (*c99_binop_t)(int, int);

typedef struct c99_pair { int a, b; } c99_pair_t;

struct c99_fwd;

static struct c99_fwd *c99_fwd_ptr;

struct c99_fwd { int member; };

static int c99_add(int x, int y) { return x + y; }

static int c99_mul(int x, int y) { return x * y; }

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
    int failures = g_fail;
    int before = c99_file_scope_object;
    before += 1;
    long after = before * 2L;
    int i = 0;
    c99_array3_t arr3 = {10, 20, 30};
    c99_pair_t pair = {1, 2};
    c99_binop_t ops[2];
    struct c99_fwd fwd = {5};
    c99_intptr_t p;
    int numbers[4] = {4, 5, 6, 7};
    sec_begin("04 declarations, scopes, storage classes");
    for (int loop_var = 0; loop_var < 3; ++loop_var) { /* C99 for-decl */
            i += loop_var;
        }
    CHECK(i == 3);
    CHECK(before == 101 && after == 202L);
    CHECK(c99_file_scope_object == 100);
    CHECK(c99_tentative_definition == 0);
    CHECK(c99_const_object == 7);
    c99_volatile_object = 2;
    CHECK(c99_volatile_object == 2);
    CHECK(c99_static_array[0] == 1 && c99_static_array[1] == 2);
    CHECK(c99_static_array[2] == 0 && c99_static_array[3] == 0);
    CHECK(arr3[0] == 10 && arr3[2] == 30 && sizeof arr3 == 3 * sizeof(int));
    CHECK(pair.a == 1 && pair.b == 2);
    CHECK(fwd.member == 5);
    c99_fwd_ptr = &fwd;
    CHECK(c99_fwd_ptr->member == 5);
    ops[0] = c99_add;
    ops[1] = c99_mul;
    CHECK(ops[0](3, 4) == 7);
    CHECK(ops[1](3, 4) == 12);
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
    {
    struct c99_pair { long x, y; };
    typedef struct c99_pair inner_pair;
    inner_pair ip = {3L, 4L};
    enum c99_local_enum { LOCAL_A = 5, LOCAL_B, LOCAL_C };
    CHECK(sizeof(inner_pair) == 2 * sizeof(long));
    CHECK(ip.x == 3L && ip.y == 4L);
    CHECK(LOCAL_A + LOCAL_B + LOCAL_C == 18);
    }
    return 0;
}
