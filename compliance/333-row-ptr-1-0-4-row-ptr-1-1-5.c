/* 333: CHECK(row_ptr[1][0] == 4 && (*(row_ptr + 1))[1] == 5);
 *
 * monolithic.c:10641 (arrays)
 */

#include <stdio.h>

static int c99_2d[2][3] = {{1, 2, 3}, {4, 5, 6}};

static int c99_row_sum(const int *row, size_t n)
{
    int total = 0;
    for (size_t i = 0; i < n; ++i) {
        total += row[i];
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
    int (*row_ptr)[3] = c99_2d;
    CHECK(sizeof c99_2d == 6 * sizeof(int));
    CHECK(sizeof c99_2d[0] == 3 * sizeof(int));
    CHECK(c99_2d[1][2] == 6 && *(*(c99_2d + 1) + 2) == 6);
    CHECK(c99_row_sum(c99_2d[1], 3) == 15);
    CHECK(row_ptr[1][0] == 4 && (*(row_ptr + 1))[1] == 5);
    return 0;
}
