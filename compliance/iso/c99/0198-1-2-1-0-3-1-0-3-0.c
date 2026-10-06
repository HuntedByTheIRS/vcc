/* 0198: CHECK((1 && 2) == 1 && (0 || 3) == 1 && (0 && 3) == 0);
 *
 * monolithic.c:9955 (expressions)
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
    CHECK((1 && 2) == 1 && (0 || 3) == 1 && (0 && 3) == 0);
    return 0;
}
