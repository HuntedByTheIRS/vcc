/* 0945: CHECK(read == 1);
 *
 * not in monolithic.c: added after the corpus was split, so it has no line there.
 */

#include <stdio.h>
#include <stdarg.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

static int scan_from(FILE *fp, const char *fmt, ...)
{
    va_list ap;
    int read;
    va_start(ap, fmt);
    read = vfscanf(fp, fmt, ap);
    va_end(ap);
    return read;
}

int main(void)
{
    FILE *fp = fopen("c99_945_vfscanf.txt", "w");
    int a = 0;
    int read;
    if (fp == 0) { return 1; }
    fputs("9 8", fp);
    fclose(fp);
    fp = fopen("c99_945_vfscanf.txt", "r");
    if (fp == 0) { return 2; }
    read = scan_from(fp, "%d", &a);
    fclose(fp);
    CHECK(read == 1);
    CHECK(a == 9);
    return 0;
}
