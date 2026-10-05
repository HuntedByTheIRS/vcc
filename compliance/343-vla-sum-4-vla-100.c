/* 343: CHECK(c99_vla_sum(4, vla) == 100);
 *
 * monolithic.c:10669 (arrays)
 */

#include <stdio.h>

static int c99_vla_sum(int n, int values[n]);

static int c99_vla_sum(int n, int values[n])
{
    int total = 0;
    for (int i = 0; i < n; ++i) {
        total += values[i];
    }
    return total;
}

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
    vla[0] = 10;
    vla[1] = 20;
    vla[2] = 30;
    vla[3] = 40;
    CHECK(c99_vla_sum(4, vla) == 100);
    return 0;
}
