/* 0390: CHECK(isalpha('a') && isalpha('Z') && !isalpha('1'));
 *
 * monolithic.c:10860 (characters)
 */

#include <stdio.h>
#include <ctype.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(isalpha('a') && isalpha('Z') && !isalpha('1'));
    return 0;
}
