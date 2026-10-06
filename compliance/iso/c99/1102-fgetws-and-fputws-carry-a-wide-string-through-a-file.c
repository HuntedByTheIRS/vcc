/* 1102: fgetws-and-fputws-carry-a-wide-string-through-a-file
 *
 * ISO/IEC 9899:1999 7.24.3.2: the fgetws function reads a wide string from
 * stream into the array pointed to by ws.
 */

#include <stdio.h>
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
    FILE *f = tmpfile();
    wchar_t buf[8];
    if (!f)
        return 1;
    CHECK(fputws(L"ab", f) >= 0);
    rewind(f);
    CHECK(fgetws(buf, 8, f) != NULL);
    CHECK(wcscmp(buf, L"ab") == 0);
    fclose(f);
    return 0;
}
