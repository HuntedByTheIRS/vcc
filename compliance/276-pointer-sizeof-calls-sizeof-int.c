/* 276: CHECK(c99_pointer_sizeof(calls) == sizeof(int *));
 *
 * monolithic.c:10399 (functions)
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

static size_t c99_pointer_sizeof(int *values)
{
    return sizeof values;
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
    CHECK(c99_vla_param_sum(8, calls) == 36);
    CHECK(c99_pointer_sizeof(calls) == sizeof(int *));
    return 0;
}
