/* 0088: CHECK(arr3[0] == 10 && arr3[2] == 30 && sizeof arr3 == 3 * sizeof(int));
 *
 * monolithic.c:9658 (declarations)
 */

#include <stdio.h>

typedef int c99_array3_t[3];

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    c99_array3_t arr3 = {10, 20, 30};
    CHECK(arr3[0] == 10 && arr3[2] == 30 && sizeof arr3 == 3 * sizeof(int));
    return 0;
}
