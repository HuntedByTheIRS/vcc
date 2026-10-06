/* 0798: CHECK(first[0] >= 0 && first[0] <= RAND_MAX);
 *
 * monolithic.c:11779 (utilities)
 */

#include <stdio.h>
#include <inttypes.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>

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
    int failures = g_fail;
    int *heap = malloc(10 * sizeof *heap);
    int *zeroed = calloc(10, sizeof *zeroed);
    int sorted[7] = {7, 1, 5, 3, 2, 6, 4};
    c99_pair_t pairs[4] = {{2, 9}, {1, 2}, {2, 3}, {1, 5}};
    char *end_pointer = NULL;
    size_t huge_size = (size_t)strtoumax("18446744073709551615", NULL, 10);
    char *environment = getenv("PATH");
    sec_begin("16 general utilities");
    CHECK(heap != NULL && zeroed != NULL);
    if (heap != NULL) {
            for (int i = 0; i < 10; ++i) {
                heap[i] = i * i;
            }
            CHECK(heap[9] == 81);
            heap = realloc(heap, 20 * sizeof *heap);
            CHECK(heap != NULL);
            if (heap != NULL) {
                CHECK(heap[9] == 81);              /* contents preserved */
                heap[19] = 999;
                CHECK(heap[19] == 999);
            }
            free(heap);
        }
    if (zeroed != NULL) {
            CHECK(zeroed[0] == 0 && zeroed[9] == 0);
            zeroed = realloc(zeroed, 4 * sizeof *zeroed);   /* shrink */
            CHECK(zeroed != NULL);
            free(zeroed);
        }
    free(NULL);
    CHECK(realloc(NULL, 4) != NULL);
    {
            /* realloc(ptr, 0) may return NULL or a pointer that must be freed. */
            void *shrunk_to_nothing = realloc(malloc(8), 0);
            free(shrunk_to_nothing);
        }
    {
            /* An impossible size must fail cleanly rather than crash.  C99 does
             * not require errno to be set for allocation failures, and an
             * optimizer may fold away a malloc/free pair whose result it can
             * predict, so the call goes through a volatile function pointer to
             * keep the real allocation. */
            void *(*volatile allocate)(size_t) = malloc;
            void *impossible;
            CHECK(huge_size > (size_t)PTRDIFF_MAX);
            impossible = allocate(huge_size);
            CHECK(impossible == NULL);
            free(impossible);
        }
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
    CHECK(abs(-5) == 5 && labs(-5L) == 5L && llabs(-5LL) == 5LL);
    {
            div_t dq = div(17, 5);
            ldiv_t ldq = ldiv(17L, 5L);
            lldiv_t lldq = lldiv(17LL, 5LL);
            imaxdiv_t idq = imaxdiv((intmax_t)17, (intmax_t)5);
            CHECK(dq.quot == 3 && dq.rem == 2);
            CHECK(ldq.quot == 3L && ldq.rem == 2L);
            CHECK(lldq.quot == 3LL && lldq.rem == 2LL);
            CHECK(idq.quot == 3 && idq.rem == 2);
            CHECK(imaxabs((intmax_t)-5) == 5);
        }
    {
    int first[4], second[4];
    srand(1);
    for (int i = 0; i < 4; ++i) {
                first[i] = rand();
            }
    srand(1);
    for (int i = 0; i < 4; ++i) {
                second[i] = rand();
            }
    CHECK(first[0] == second[0] && first[3] == second[3]);
    CHECK(first[0] >= 0 && first[0] <= RAND_MAX);
    srand((unsigned)time(NULL));
    CHECK(rand() >= 0 && rand() <= RAND_MAX);
    CHECK(RAND_MAX >= 32767);
    }
    return 0;
}
