/* 0235: CHECK(sizeof(1 ? 1 : 1.0) == sizeof(double));
 *
 * monolithic.c:10012 (expressions)
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
    CHECK(sizeof(1 ? 1 : 1.0) == sizeof(double));
    return 0;
}
