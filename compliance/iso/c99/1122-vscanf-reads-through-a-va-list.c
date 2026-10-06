/* 1122: vscanf-reads-through-a-va-list
 *
 * ISO/IEC 9899:1999 7.19.6.9: the vscanf function is equivalent to scanf
 * with the variable argument list replaced by arg.
 */

#include <stdarg.h>
#include <stdio.h>

static int from(const char *fmt, ...)
{
    va_list ap;
    int r;
    va_start(ap, fmt);
    r = vscanf(fmt, ap);
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
    FILE *f = fopen("vscanf_input.txt", "w");
    int v = 0;
    if (!f)
        return 1;
    fputs("41", f);
    fclose(f);
    if (freopen("vscanf_input.txt", "r", stdin) == NULL)
        return 1;
    CHECK(from("%d", &v) == 1);
    CHECK(v == 41);
    return 0;
}
