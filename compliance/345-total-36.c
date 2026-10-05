/* 345: CHECK(total == 36);
 *
 * monolithic.c:10681 (arrays)
 */

#include <stdio.h>

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
    int rows = 2, cols = 3;
    int matrix[rows][cols];
    int total = 0;
    for (int i = 0; i < rows; ++i) {
                for (int j = 0; j < cols; ++j) {
                    matrix[i][j] = i * 10 + j;
                    total += matrix[i][j];
                }
            }
    CHECK(sizeof matrix == (size_t)(rows * cols) * sizeof(int));
    CHECK(total == 36);
    }
    return 0;
}
