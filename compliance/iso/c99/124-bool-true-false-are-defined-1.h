/* 124: CHECK(__bool_true_false_are_defined == 1);
 *
 * monolithic.c:9801 (types)
 */

#include <stdio.h>
#include <stdbool.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(__bool_true_false_are_defined == 1);
    return 0;
}
