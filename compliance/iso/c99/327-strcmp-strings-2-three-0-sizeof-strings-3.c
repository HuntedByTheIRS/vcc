/* 327: CHECK(strcmp(strings[2], "three") == 0 && sizeof strings == 3 * sizeof(char *));
 *
 * monolithic.c:10634 (arrays)
 */

#include <stdio.h>
#include <stddef.h>
#include <string.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    const char *strings[3] = {"one", "two", "three"};
    CHECK(strcmp(strings[2], "three") == 0 && sizeof strings == 3 * sizeof(char *));
    return 0;
}
