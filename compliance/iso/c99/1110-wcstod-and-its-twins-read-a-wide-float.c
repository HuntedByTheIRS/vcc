/* 1110: wcstod-and-its-twins-read-a-wide-float
 *
 * ISO/IEC 9899:1999 7.24.4.1.1: the wcstod, wcstof and wcstold functions
 * convert the initial portion of the wide string to float, double and long
 * double.
 */

#include <wchar.h>

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
    CHECK(wcstod(L"0.5", NULL) == 0.5);
    CHECK(wcstof(L"0.5", NULL) == 0.5f);
    CHECK(wcstold(L"0.5", NULL) == 0.5L);
    return 0;
}
