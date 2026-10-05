/* 324: CHECK(sizeof exact == 3 && exact[0] == 'a' && exact[2] == 'c');
 *
 * monolithic.c:10631 (arrays)
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
    char exact[3];
    memcpy(exact, "abc", 3);
    CHECK(sizeof exact == 3 && exact[0] == 'a' && exact[2] == 'c');
    return 0;
}
