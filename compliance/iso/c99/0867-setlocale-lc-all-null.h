/* 0867: CHECK(setlocale(LC_ALL, "") != NULL);
 *
 * monolithic.c:12004 (runtime)
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
    char saved[64];
    CHECK(current != NULL);
    snprintf(saved, sizeof saved, "%s", current != NULL ? current : "C");
    CHECK(setlocale(LC_ALL, "") != NULL);
    }
    return 0;
}
