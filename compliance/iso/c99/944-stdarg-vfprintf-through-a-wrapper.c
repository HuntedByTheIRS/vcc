/* 944: CHECK(n == 2);
 *
 * not in monolithic.c: added after the corpus was split, so it has no line there.
 */

#include <stdio.h>
#include <stdarg.h>
#include <string.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

static int dump(FILE *fp, const char *fmt, ...)
{
    va_list ap;
    int written;
    va_start(ap, fmt);
    written = vfprintf(fp, fmt, ap);
    va_end(ap);
    return written;
}

int main(void)
{
    FILE *fp = fopen("c99_944_vfprintf.txt", "w");
    int n;
    char back[8];
    if (fp == 0) { return 1; }
    n = dump(fp, "%d", 42);
    fclose(fp);
    CHECK(n == 2);
    fp = fopen("c99_944_vfprintf.txt", "r");
    if (fp == 0) { return 2; }
    if (fgets(back, sizeof back, fp) == 0) { return 3; }
    fclose(fp);
    CHECK(strcmp(back, "42") == 0);
    return 0;
}
