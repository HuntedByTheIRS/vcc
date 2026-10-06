/* 319: CHECK(sizeof partial == 6 * sizeof(int));
 *
 * monolithic.c:10626 (arrays)
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
    return 0;
}
