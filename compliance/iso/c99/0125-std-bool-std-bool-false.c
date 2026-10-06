/* 0125: CHECK(std_bool && !std_bool_false);
 *
 * monolithic.c:9802 (types)
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
    bool std_bool = true;
    bool std_bool_false = false;
    CHECK(std_bool && !std_bool_false);
    return 0;
}
