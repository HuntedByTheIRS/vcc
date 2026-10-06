/* 273: CHECK(c99_vla_star_sum(3, star_calls) == 60);
 *
 * monolithic.c:10391 (functions)
 */

#include <stdio.h>

static int c99_vla_param_sum(int n, int values[n]);

static int c99_vla_param_sum(int n, int values[n])
{
    int total = 0;
    for (int i = 0; i < n; ++i) {
        total += values[i];
    }
    return total;
}

static int c99_vla_star_sum(int n, int values[n]);

static int c99_vla_star_sum(int n, int values[n])
{
    return c99_vla_param_sum(n, values);
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
    int calls[8] = {1, 2, 3, 4, 5, 6, 7, 8};
    int star_calls[3] = {10, 20, 30};
    CHECK(c99_vla_param_sum(8, calls) == 36);
    CHECK(c99_vla_star_sum(3, star_calls) == 60);
    return 0;
}
