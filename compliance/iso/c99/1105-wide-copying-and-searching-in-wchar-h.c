/* 1105: wide-copying-and-searching-in-wchar-h
 *
 * ISO/IEC 9899:1999 7.24.4.2.1: the wcscpy function copies the wide string
 * pointed to by s2 into the array pointed to by s1.
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
    wchar_t a[8];
    wchar_t b[8];
    wmemcpy(a, L"abcd", 5);
    wmemmove(b, a, 5);
    CHECK(wcscmp(a, L"abcd") == 0);
    CHECK(wcscmp(b, L"abcd") == 0);
    wcsncpy(b, L"xy", 2);
    b[2] = L'\0';
    CHECK(wcscmp(b, L"xy") == 0);
    wcscat(a, L"efg");
    CHECK(wcslen(a) == 7);
    wcsncat(a, L"xyz", 2);
    CHECK(wcslen(a) == 9 && a[8] == L'y');
    CHECK(wmemcmp(L"ab", L"ab", 2) == 0);
    CHECK(wmemchr(L"ab", L'b', 2) != NULL);
    CHECK(wcschr(L"ab", L'b') != NULL);
    CHECK(wcsrchr(L"ab", L'b') != NULL);
    CHECK(wcsstr(L"abc", L"bc") != NULL);
    CHECK(wcspbrk(L"abc", L"cb") != NULL);
    CHECK(wcsspn(L"aab", L"a") == 2);
    CHECK(wcscspn(L"aab", L"b") == 2);
    wmemset(a, L'z', 3);
    CHECK(a[0] == L'z' && a[3] == L'd');
    return 0;
}
