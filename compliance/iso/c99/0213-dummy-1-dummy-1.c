/* 0213: CHECK((dummy = 1, dummy) == 1);
 *
 * monolithic.c:9974 (expressions)
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
    int dummy = 0;
    CHECK((dummy = 1, dummy) == 1);
    }
    return 0;
}
