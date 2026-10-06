/* 0866: CHECK(current != NULL);
 *
 * monolithic.c:12002 (runtime)
 */

#include <stdio.h>
#include <locale.h>
#include <stddef.h>

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
    const char *current = setlocale(LC_ALL, NULL);
    CHECK(current != NULL);
    }
    return 0;
}
