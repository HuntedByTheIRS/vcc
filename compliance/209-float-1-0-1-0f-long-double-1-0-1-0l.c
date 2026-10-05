/* 209: CHECK((float)1.0 == 1.0f && (long double)1.0 == 1.0L);
 *
 * monolithic.c:9968 (expressions)
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
    CHECK((float)1.0 == 1.0f && (long double)1.0 == 1.0L);
    return 0;
}
