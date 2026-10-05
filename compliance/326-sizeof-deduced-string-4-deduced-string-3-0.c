/* 326: CHECK(sizeof deduced_string == 4 && deduced_string[3] == '\0');
 *
 * monolithic.c:10633 (arrays)
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
    char deduced_string[] = "abc";
    CHECK(sizeof deduced_string == 4 && deduced_string[3] == '\0');
    return 0;
}
