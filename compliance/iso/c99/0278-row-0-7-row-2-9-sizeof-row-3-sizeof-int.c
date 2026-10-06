/* 0278: CHECK((*row)[0] == 7 && (*row)[2] == 9 && sizeof *row == 3 * sizeof(int));
 *
 * monolithic.c:10402 (functions)
 */

#include <stdio.h>

static int c99_three_row[3] = {7, 8, 9};

static int (*c99_get_three(void))[3]
{
    return &c99_three_row;
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
    int (*row)[3];
    row = c99_get_three();
    CHECK((*row)[0] == 7 && (*row)[2] == 9 && sizeof *row == 3 * sizeof(int));
    return 0;
}
