/* 0286: CHECK((*fp())[1] == 8);
 *
 * monolithic.c:10416 (functions)
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
    {
    int (*(*fp)(void))[3] = c99_get_three;
    CHECK((*fp())[1] == 8);
    }
    return 0;
}
