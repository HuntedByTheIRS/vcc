/* 1112: the-wide-printf-family-writes-to-a-stream
 *
 * ISO/IEC 9899:1999 7.24.2.1: the fwprintf function writes output to the
 * stream pointed to by stream under the control of the wide string.
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
    wchar_t buf[16];
    if (!f)
        return 1;
    CHECK(fwprintf(f, L"%d", 41) == 2);
    rewind(f);
    CHECK(fgetws(buf, 16, f) != NULL);
    CHECK(wcscmp(buf, L"41") == 0);
    fclose(f);
    return 0;
}
