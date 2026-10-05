/* 161: CHECK(wc == L'x' && sizeof(wchar_t) >= 1);
 *
 * monolithic.c:9851 (types)
 */

#include <stdio.h>
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
    wchar_t wc = L'x';
    CHECK(wc == L'x' && sizeof(wchar_t) >= 1);
    return 0;
}
