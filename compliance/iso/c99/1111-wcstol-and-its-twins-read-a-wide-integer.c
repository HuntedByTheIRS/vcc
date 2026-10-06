/* 1111: wcstol-and-its-twins-read-a-wide-integer
 *
 * ISO/IEC 9899:1999 7.24.4.1.2: the wcstol, wcstoll, wcstoul and wcstoull
 * functions convert the initial portion of the wide string to long and long
 * long.
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
    CHECK(wcstol(L"41", NULL, 10) == 41L);
    CHECK(wcstoll(L"4294967296", NULL, 10) == 4294967296LL);
    CHECK(wcstoul(L"41", NULL, 10) == 41UL);
    CHECK(wcstoull(L"18446744073709551615", NULL, 10) == 18446744073709551615ULL);
    return 0;
}
