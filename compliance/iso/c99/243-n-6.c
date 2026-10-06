/* 243: CHECK(n == 6);
 *
 * monolithic.c:10064 (control-flow)
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
    int n = 0;
    int i = 0;
    for (i = 0; i < 3; ++i) {
            if (i == 0) {
                n += 1;
            } else if (i == 1) {
                n += 2;
            } else {
                n += 3;
            }
        }
    CHECK(n == 6);
    return 0;
}
