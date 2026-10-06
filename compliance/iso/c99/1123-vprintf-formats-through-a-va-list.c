/* 1123: vprintf-formats-through-a-va-list
 *
 * ISO/IEC 9899:1999 7.19.6.8: the vprintf function is equivalent to printf
 * with the variable argument list replaced by arg.
 */

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

static int through(const char *fmt, ...)
{
    va_list ap;
    int r;
    va_start(ap, fmt);
    r = vprintf(fmt, ap);
    va_end(ap);
    return r;
}

/* vprintf writes to stdout and the runner reads stdout as a finding, so this
 * check sends stdout to a file and reads what landed there. A check that fails
 * writes its FAIL line into that file rather than into the run's output; the
 * exit status is what reports it. */
#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    char buf[8];
    int n;
    FILE *f;
    if (freopen("vprintf_output.txt", "w", stdout) == NULL)
        return 1;
    n = through("%d", 41);
    fflush(stdout);
    f = fopen("vprintf_output.txt", "r");
    if (!f)
        return 1;
    if (fgets(buf, sizeof buf, f) == NULL)
        buf[0] = '\0';
    fclose(f);
    CHECK(n == 2);
    CHECK(strcmp(buf, "41") == 0);
    return 0;
}
