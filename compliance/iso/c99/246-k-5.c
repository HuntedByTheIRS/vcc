/* 246: CHECK(k == 5);
 *
 * monolithic.c:10088 (control-flow)
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
    int k = 0, sum = 0;
    while (k < 5) { sum += k; ++k; }
    CHECK(sum == 10 && k == 5);
    k = 100;
    do { --k; } while (k > 5);
    CHECK(k == 5);
    }
    return 0;
}
