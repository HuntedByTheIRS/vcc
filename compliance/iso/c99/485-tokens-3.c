/* 485: CHECK(tokens == 3);
 *
 * monolithic.c:11099 (strings)
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
    {
    char text[] = "one,two,,three";
    const char *token = strtok(text, ",");
    int tokens = 0;
    while (token != NULL) {
                ++tokens;
                token = strtok(NULL, ",");
            }
    CHECK(tokens == 3);
    }
    return 0;
}
