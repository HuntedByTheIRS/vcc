/* 0320: CHECK(partial[0] == 1 && partial[1] == 2 && partial[2] == 0);
 *
 * monolithic.c:10627 (arrays)
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
    int partial[6] = {1, 2};
    CHECK(sizeof partial == 6 * sizeof(int));
    CHECK(partial[0] == 1 && partial[1] == 2 && partial[2] == 0);
    return 0;
}
