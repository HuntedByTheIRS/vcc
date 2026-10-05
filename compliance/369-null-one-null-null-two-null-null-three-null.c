/* 369: CHECK(null_one == NULL && null_two == NULL && null_three == NULL);
 *
 * monolithic.c:10779 (pointers)
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
    int *null_one = 0;
    int *null_two = NULL;
    int *null_three = (void *)0;
    CHECK(null_one == NULL && null_two == NULL && null_three == NULL);
    }
    return 0;
}
