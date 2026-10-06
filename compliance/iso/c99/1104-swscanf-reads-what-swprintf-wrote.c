/* 1104: swscanf-reads-what-swprintf-wrote
 *
 * ISO/IEC 9899:1999 7.24.2.4: the swscanf function reads input from the
 * wide string ws.
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
    wchar_t buf[16];
    int v = 0;
    wchar_t word[8];
    CHECK(swprintf(buf, 16, L"%d %ls", 41, L"ok") == 5);
    CHECK(swscanf(buf, L"%d %ls", &v, word) == 2);
    CHECK(v == 41 && wcscmp(word, L"ok") == 0);
    return 0;
}
