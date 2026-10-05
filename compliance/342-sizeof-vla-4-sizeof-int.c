/* 342: CHECK(sizeof vla == 4 * sizeof(int));
 *
 * monolithic.c:10664 (arrays)
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
    const int not_a_constant_expression = 4;
    int vla[not_a_constant_expression];
    CHECK(sizeof vla == 4 * sizeof(int));
    return 0;
}
