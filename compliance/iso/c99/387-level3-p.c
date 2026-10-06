/* 387: CHECK(**level3 == p);
 *
 * monolithic.c:10827 (pointers)
 */

#include <stdio.h>
#include <stddef.h>

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

typedef struct c99_pair { int a, b; } c99_pair_t;

static int c99_pointer_add(int a, int b) { return a + b; }

static int c99_pointer_mul(int a, int b) { return a * b; }

static int printf_like_noop(const char *unused, ...);

static int (*const c99_pointer_table[2])(int, int) = {c99_pointer_add, c99_pointer_mul};

struct c99_outer {
    int pad;
    c99_pair_t inner;
};

static int printf_like_noop(const char *unused, ...)
{
    return unused != NULL ? 0 : 1;
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
    int values[5] = {0, 10, 20, 30, 40};
    int *p = values;
    int *q = values + 4;
    const int *pc = values;
    int *const cp = values;
    int **pp = &p;
    void *vp = values;
    char *bytes = (char *)values;
    struct c99_outer outer = {0, {7, 8}};
    c99_pair_t *inner_ptr = &outer.inner;
    int (*row)[5] = &values;
    int *ptrs[3] = {&values[0], &values[1], &values[2]};
    sec_begin("11 pointers");
    CHECK(p == values && *p == 0 && p[1] == 10 && *(p + 2) == 20);
    CHECK(q - p == 4 && p + 4 == q && q > p && p < q);
    CHECK(pc == values && *pc == 0);
    *cp = 1;
    CHECK(values[0] == 1);
    CHECK(*pp == p && **pp == 1);
    CHECK((int *)vp == values && ((int *)vp)[1] == 10);
    CHECK(sizeof p == sizeof(int *) && sizeof(void *) == sizeof(char *));
    CHECK(sizeof p == sizeof row);
    CHECK((void *)(bytes + sizeof(int)) == (void *)(values + 1));
    CHECK(bytes[0] == 1 && bytes[sizeof(int)] == 10);
    {
            int *null_one = 0;
            int *null_two = NULL;
            int *null_three = (void *)0;
            CHECK(null_one == NULL && null_two == NULL && null_three == NULL);
            CHECK(!null_one && !(p == NULL));
        }
    CHECK((*row)[2] == 20 && sizeof *row == 5 * sizeof(int));
    CHECK(sizeof row == sizeof(int (*)[5]));
    CHECK(*ptrs[1] == 10 && *ptrs[2] == 20);
    CHECK(sizeof ptrs == 3 * sizeof(int *));
    CHECK(*values == values[0]);
    CHECK(c99_pointer_table[0](3, 4) == 7);
    CHECK(c99_pointer_table[1](3, 4) == 12);
    CHECK((*c99_pointer_table[0])(3, 4) == 7);
    {
            int (*chosen)(int, int) = c99_pointer_table[1];
            int (*variadic)(const char *, ...) = printf_like_noop;
            CHECK(chosen(5, 6) == 30);
            CHECK(variadic("...") == 0);
            CHECK(chosen == c99_pointer_table[1] && chosen != c99_pointer_table[0]);
        }
    {
            struct c99_outer *recovered =
                (struct c99_outer *)(void *)((char *)inner_ptr -
                                             offsetof(struct c99_outer, inner));
            CHECK(recovered == &outer);
            CHECK(recovered->inner.a == 7 && recovered->inner.b == 8);
        }
    {
            void *as_void = p;
            int *back = (int *)as_void;
            char *as_char = (char *)(void *)p;
            CHECK(back == p && as_char == (char *)p);
            CHECK((void *)0 == (int *)0);
        }
    {
    int **level2 = &p;
    int ***level3 = &level2;
    CHECK(***level3 == *p);
    CHECK(**level3 == p);
    CHECK(*level3 == &p);
    }
    return 0;
}
