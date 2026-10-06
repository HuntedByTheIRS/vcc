/* 0248: CHECK(i == 5 && j == 5);
 *
 * monolithic.c:10096 (control-flow)
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
    int j = 0;
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
    {
    for (i = 0, j = 10; i < j; i++, j--) ;
    CHECK(i == 5 && j == 5);
    }
    return 0;
}
