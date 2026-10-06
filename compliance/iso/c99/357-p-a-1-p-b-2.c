/* 357: CHECK(p.a == 1 && p.b == 2);
 *
 * monolithic.c:10711 (arrays)
 */

#include <stdio.h>

typedef struct c99_pair { int a, b; } c99_pair_t;

struct c99_node {                    /* self-referential structure */
    int value;
    struct c99_node *next;
};

struct c99_nested {                  /* struct inside struct inside struct */
    struct {
        int x;
        int y;
    } point;
    union {
        int as_int;
        char as_bytes[sizeof(int)];
    } pun;
    struct c99_node chain[2];
};

static int c99_pair_sum(c99_pair_t p);

static int c99_pair_sum(c99_pair_t p)
{
    return p.a + p.b;
}

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
            int *arr = (int[]){10, 20, 30};
            c99_pair_t *pr = &(c99_pair_t){3, 4};
            int sum = c99_row_sum((const int[]){1, 2, 3, 4}, 4);
            CHECK(arr[0] == 10 && arr[2] == 30);
            arr[1] = 21;                      /* compound literals are lvalues */
            CHECK(arr[1] == 21);
            CHECK(pr->a == 3 && pr->b == 4);
            pr->a = 5;
            CHECK(pr->a == 5);
            CHECK(sum == 10);
            CHECK(c99_pair_sum((c99_pair_t){1, 1}) == 2);
            CHECK(sizeof (int[]){1, 2, 3} == 3 * sizeof(int));
            CHECK(sizeof (c99_pair_t){1, 2} == sizeof(c99_pair_t));
        }
    {
    struct c99_nested n = {.point = {.y = 2, .x = 1}, .chain[1] = {4, NULL}};
    c99_pair_t p = {.b = 2, .a = 1};
    CHECK(n.point.x == 1 && n.point.y == 2);
    CHECK(n.chain[1].value == 4 && n.chain[0].value == 0);
    CHECK(p.a == 1 && p.b == 2);
    }
    return 0;
}
