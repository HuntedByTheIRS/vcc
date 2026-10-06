/* 1114: fwscanf-reads-what-fwprintf-wrote
 *
 * ISO/IEC 9899:1999 7.24.2.3: the fwscanf function reads input from the
 * stream under the control of the wide string format.
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
    int v = 0;
    if (!f)
        return 1;
    fputws(L"41", f);
    rewind(f);
    CHECK(fwscanf(f, L"%d", &v) == 1);
    CHECK(v == 41);
    fclose(f);
    return 0;
}
