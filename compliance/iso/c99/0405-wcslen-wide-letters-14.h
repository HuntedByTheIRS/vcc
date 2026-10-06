/* 0405: CHECK(wcslen(wide_letters) == 14);
 *
 * monolithic.c:10875 (characters)
 */

#include <stdio.h>
#include <stdarg.h>
#include <stddef.h>
#include <wchar.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    wchar_t wide_letters[] = L"abcXYZ123 \t.,;";
    CHECK(wcslen(wide_letters) == 14);
    return 0;
}
