/* 633: CHECK(snprintf(formatted, sizeof formatted, "%d", -42) == 3);
 *
 * monolithic.c:11441 (stdio)
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
    char formatted[128];
    CHECK(snprintf(formatted, sizeof formatted, "%d", -42) == 3);
    return 0;
}
