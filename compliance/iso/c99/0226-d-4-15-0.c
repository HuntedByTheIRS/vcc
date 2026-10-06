/* 0226: CHECK(d * 4 == 15.0);
 *
 * monolithic.c:9997 (expressions)
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
    double d = 3.75;
    CHECK(d * 4 == 15.0);
    return 0;
}
