/* 107: CHECK(sizeof(c99_vla_t) == 3 * sizeof(int));
 *
 * monolithic.c:9716 (declarations)
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
    int n = 3;
    typedef int c99_vla_t[n];
    CHECK(sizeof(c99_vla_t) == 3 * sizeof(int));
    }
    return 0;
}
