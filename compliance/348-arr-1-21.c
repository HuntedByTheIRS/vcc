/* 348: CHECK(arr[1] == 21);
 *
 * monolithic.c:10693 (arrays)
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
    int *arr = (int[]){10, 20, 30}
    ;
    CHECK(arr[0] == 10 && arr[2] == 30);
    arr[1] = 21;
    CHECK(arr[1] == 21);
    }
    return 0;
}
