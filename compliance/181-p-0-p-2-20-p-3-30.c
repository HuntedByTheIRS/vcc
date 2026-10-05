/* 181: CHECK(*p == 0 && p[2] == 20 && *(p + 3) == 30);
 *
 * monolithic.c:9928 (expressions)
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
    CHECK(*p == 0 && p[2] == 20 && *(p + 3) == 30);
    return 0;
}
