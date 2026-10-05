/* 111: CHECK(sizeof numbers == 4 * sizeof(int));
 *
 * monolithic.c:9723 (declarations)
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
    int numbers[4] = {4, 5, 6, 7};
    CHECK(sizeof numbers == 4 * sizeof(int));
    return 0;
}
