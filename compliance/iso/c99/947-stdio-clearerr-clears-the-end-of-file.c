/* 947: CHECK(!feof(fp));
 *
 * not in monolithic.c: added after the corpus was split, so it has no line there.
 */

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
    FILE *fp = fopen("c99_947_clearerr.txt", "w");
    int c;
    if (fp == 0) { return 1; }
    fputs("x", fp);
    fclose(fp);
    fp = fopen("c99_947_clearerr.txt", "r");
    if (fp == 0) { return 2; }
    c = getc(fp);
    CHECK(c == 'x');
    c = getc(fp);
    CHECK(c == EOF);
    CHECK(feof(fp));
    CHECK(!ferror(fp));
    clearerr(fp);
    CHECK(!feof(fp));
    CHECK(!ferror(fp));
    /* The stream is still positioned at the end, so the next read is EOF
     * again: what clearerr took back is the flag and not the position. */
    c = getc(fp);
    CHECK(c == EOF);
    fclose(fp);
    return 0;
}
