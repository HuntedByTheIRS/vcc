/* 0360: CHECK(q - p == 4 && p + 4 == q && q > p && p < q);
 *
 * monolithic.c:10761 (pointers)
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
    int values[5] = {0, 10, 20, 30, 40};
    int *p = values;
    int *q = values + 4;
    CHECK(p == values && *p == 0 && p[1] == 10 && *(p + 2) == 20);
    CHECK(q - p == 4 && p + 4 == q && q > p && p < q);
    return 0;
}
