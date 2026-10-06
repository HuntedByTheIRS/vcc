/* 0359: CHECK(p == values && *p == 0 && p[1] == 10 && *(p + 2) == 20);
 *
 * monolithic.c:10760 (pointers)
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
    CHECK(p == values && *p == 0 && p[1] == 10 && *(p + 2) == 20);
    return 0;
}
