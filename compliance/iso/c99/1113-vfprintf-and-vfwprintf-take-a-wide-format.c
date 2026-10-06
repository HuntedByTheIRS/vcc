/* 1113: vfprintf-and-vfwprintf-take-a-wide-format
 *
 * ISO/IEC 9899:1999 7.24.2.2: the vfwprintf function is equivalent to
 * fwprintf with the variable argument list replaced by arg.
 */

#include <stdarg.h>
#include <stdio.h>
#include <wchar.h>

static int wide(FILE *f, const wchar_t *fmt, ...)
{
    va_list ap;
    int r;
    va_start(ap, fmt);
    r = vfwprintf(f, fmt, ap);
    va_end(ap);
    return r;
}

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
    CHECK(wide(f, L"%d", 7) == 1);
    rewind(f);
    CHECK(fgetws(buf, 16, f) != NULL);
    CHECK(wcscmp(buf, L"7") == 0);
    fclose(f);
    return 0;
}
