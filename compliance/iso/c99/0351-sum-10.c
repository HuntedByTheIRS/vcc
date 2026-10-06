/* 0351: CHECK(sum == 10);
 *
 * monolithic.c:10697 (arrays)
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
    int *flat_view = &c99_2d[0][0];
    CHECK(sizeof c99_2d == 6 * sizeof(int));
    CHECK(sizeof c99_2d[0] == 3 * sizeof(int));
    CHECK(c99_2d[1][2] == 6 && *(*(c99_2d + 1) + 2) == 6);
    CHECK(c99_row_sum(c99_2d[1], 3) == 15);
    CHECK(flat_view[4] == 5 && flat_view[5] == 6);
    CHECK(flat_view + 3 == c99_2d[1]);
    {
            int rows = 2, cols = 3;
            int matrix[rows][cols];                       /* 2-D VLA */
            int total = 0;
            for (int i = 0; i < rows; ++i) {
                for (int j = 0; j < cols; ++j) {
                    matrix[i][j] = i * 10 + j;
                    total += matrix[i][j];
                }
            }
            CHECK(sizeof matrix == (size_t)(rows * cols) * sizeof(int));
            CHECK(total == 36);                  /* 0+1+2 + 10+11+12 */
            CHECK(matrix[1][2] == 12);
        }
    {
    int sum = c99_row_sum((const int[]){1, 2, 3, 4}, 4);
    CHECK(sum == 10);
    }
    return 0;
}
