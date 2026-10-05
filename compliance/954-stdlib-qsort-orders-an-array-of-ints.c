/* 954: CHECK(v[i] == i + 1);
 *
 * not in monolithic.c: added after the corpus was split, so it has no line there.
 */

#include <stdio.h>
#include <stdlib.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

static int compare_ints(const void *left, const void *right)
{
    int a = *(const int *)left;
    int b = *(const int *)right;
    return (a > b) - (a < b);
}

int main(void)
{
    int v[5] = { 4, 1, 5, 2, 3 };
    int i;
    qsort(v, 5, sizeof(int), compare_ints);
    for (i = 0; i < 5; i++) {
        CHECK(v[i] == i + 1);
    }
    return 0;
}
