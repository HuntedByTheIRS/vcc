/* 0240: CHECK((*row)[1] == 10 && sizeof *row == 5 * sizeof(int));
 *
 * monolithic.c:10021 (expressions)
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
    int arr[5] = {0, 10, 20, 30, 40};
    int *p = arr;
    int **pp = &p;
    CHECK(*p == 0 && p[2] == 20 && *(p + 3) == 30);
    CHECK(sizeof p == sizeof(int *));
    CHECK(p + 4 == &arr[4] && &arr[4] - p == 4);
    CHECK(p < p + 1 && p + 1 > p && p == &arr[0] && p != NULL);
    CHECK(*pp == p && **pp == 0);
    {
    int (*row)[5] = &arr;
    CHECK((*row)[1] == 10 && sizeof *row == 5 * sizeof(int));
    }
    return 0;
}
