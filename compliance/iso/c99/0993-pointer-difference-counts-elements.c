/* 0993: CHECK(back - front == 4);
 *
 * not in monolithic.c: added after the corpus was split, so it has no line there.
 */

#include <stdio.h>
#include <stddef.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    int array[8];
    int *front = array + 3;
    int *back = array + 7;
    CHECK(back - front == 4);
    CHECK(front - array == 3);
    CHECK(front - front == 0);
    CHECK(sizeof(back - front) == sizeof(ptrdiff_t));
    return 0;
}
