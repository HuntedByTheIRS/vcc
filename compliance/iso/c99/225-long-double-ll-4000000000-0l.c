/* 225: CHECK((long double)ll == 4000000000.0L);
 *
 * monolithic.c:9996 (expressions)
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
    long long ll = 4000000000LL;
    CHECK((long double)ll == 4000000000.0L);
    return 0;
}
