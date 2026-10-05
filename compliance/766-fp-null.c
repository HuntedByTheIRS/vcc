/* 766: CHECK(fp != NULL);
 *
 * monolithic.c:11620 (stdio)
 */

#include <stdio.h>
#include <inttypes.h>
#include <math.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <tgmath.h>

static int c99_scan_into(const char *source, const char *fmt, ...)
{
    va_list ap;
    int converted;

    va_start(ap, fmt);
    converted = vsscanf(source, fmt, ap);   /* vsscanf is a C99 addition */
    va_end(ap);
    return converted;
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
    char formatted[128];
    char word[16];
    int consumed = 0;
    int int_a = 0, int_b = 0;
    unsigned int uint_a = 0;
    double double_value = 0.0;
    float float_value = 0.0f;
    double d = 3.14159;
    CHECK(BUFSIZ > 0 && FILENAME_MAX > 0 && FOPEN_MAX > 0 && TMP_MAX > 0);
    CHECK(SEEK_SET == 0 && SEEK_CUR == 1 && SEEK_END == 2);
    CHECK(snprintf(formatted, sizeof formatted, "%d", -42) == 3);
    CHECK(strcmp(formatted, "-42") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%i", 42) == 2);
    CHECK(strcmp(formatted, "42") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%u", 42u) == 2);
    CHECK(strcmp(formatted, "42") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%o", 8u) == 2);
    CHECK(strcmp(formatted, "10") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%#o", 8u) == 3);
    CHECK(strcmp(formatted, "010") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%x", 255u) == 2);
    CHECK(strcmp(formatted, "ff") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%X", 255u) == 2);
    CHECK(strcmp(formatted, "FF") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%#x", 255u) == 4);
    CHECK(strcmp(formatted, "0xff") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%c", 'A') == 1);
    CHECK(strcmp(formatted, "A") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%s", "abc") == 3);
    CHECK(strcmp(formatted, "abc") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%.2s", "abc") == 2);
    CHECK(strcmp(formatted, "ab") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%5d", 42) == 5);
    CHECK(strcmp(formatted, "   42") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%-5d|", 42) == 6);
    CHECK(strcmp(formatted, "42   |") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%05d", 42) == 5);
    CHECK(strcmp(formatted, "00042") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%+d", 42) == 3);
    CHECK(strcmp(formatted, "+42") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "% d", 42) == 3);
    CHECK(strcmp(formatted, " 42") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%*d", 5, 42) == 5);
    CHECK(strcmp(formatted, "   42") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%.*f", 2, d) == 4);
    CHECK(strcmp(formatted, "3.14") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%.3f", d) == 5);
    CHECK(strcmp(formatted, "3.142") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%e", 1234.5) == 12);
    CHECK(strcmp(formatted, "1.234500e+03") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%g", 0.0001) == 6);
    CHECK(strcmp(formatted, "0.0001") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%.3g", 1234.5) == 8);
    CHECK(strcmp(formatted, "1.23e+03") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%hhd", (int)(signed char)-1) == 2);
    CHECK(strcmp(formatted, "-1") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%hd", (int)(short)-2) == 2);
    CHECK(strcmp(formatted, "-2") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%ld", 123456789L) == 9);
    CHECK(strcmp(formatted, "123456789") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%lld", -1234567890123LL) == 14);
    CHECK(strcmp(formatted, "-1234567890123") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%jd", (intmax_t)-5) == 2);
    CHECK(strcmp(formatted, "-5") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%zu", (size_t)7) == 1);
    CHECK(strcmp(formatted, "7") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%td", (ptrdiff_t)-3) == 2);
    CHECK(strcmp(formatted, "-3") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%Lf", 1.5L) == 8);
    CHECK(strcmp(formatted, "1.500000") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "100%%") == 4);
    CHECK(strcmp(formatted, "100%") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "abc%n", &consumed) == 3);
    CHECK(consumed == 3);
    CHECK(snprintf(formatted, sizeof formatted, "%a", 1.0) == 6);
    CHECK(strcmp(formatted, "0x1p+0") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%A", 2.0) == 6);
    CHECK(strcmp(formatted, "0X1P+1") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%p", (void *)&consumed) > 0);
    CHECK(snprintf(formatted, sizeof formatted, "%.0f", 2.5) == 1);
    CHECK(strcmp(formatted, "2") == 0);
    {
            volatile size_t bound = 4;
            CHECK(snprintf(formatted, bound, "%s", "truncated") == 9);
            CHECK(strcmp(formatted, "tru") == 0);
        }
    CHECK(snprintf(formatted, 0, "%d", 1) == 1);
    CHECK(sprintf(formatted, "%s-%d", "sprintf", 1) == 9);
    CHECK(strcmp(formatted, "sprintf-1") == 0);
    CHECK(sscanf("42 -7 word 3.5", "%d %d %15s", &int_a, &int_b, word) == 3);
    CHECK(int_a == 42 && int_b == -7 && strcmp(word, "word") == 0);
    CHECK(sscanf("3.5", "%lf", &double_value) == 1 && double_value == 3.5);
    CHECK(sscanf("0x1f", "%x", &uint_a) == 1 && uint_a == 0x1fu);
    CHECK(sscanf("077", "%o", &uint_a) == 1 && uint_a == 63u);
    CHECK(sscanf("abc123", "%3s%n", word, &consumed) == 1);
    CHECK(consumed == 3 && strcmp(word, "abc") == 0);
    CHECK(sscanf("9 8", "%*d %d", &int_b) == 1 && int_b == 8);
    CHECK(sscanf("z", "%d", &int_a) == 0);
    CHECK(sscanf("", "%d", &int_a) == EOF);
    {
            signed char narrow = 0;
            CHECK(sscanf("127", "%hhd", &narrow) == 1 && narrow == 127);
            narrow = 0;
            CHECK(sscanf("-128", "%hhd", &narrow) == 1 && narrow == -128);
        }
    CHECK(c99_scan_into("12/34", "%d/%d", &int_a, &int_b) == 2);
    CHECK(int_a == 12 && int_b == 34);
    CHECK(c99_scan_into("2.5", "%f", &float_value) == 1 && float_value == 2.5f);
    {
            FILE *fp = tmpfile();
            char line[32];
            fpos_t position;

            if (fp != NULL) {
                CHECK(fputs("first\n", fp) >= 0);
                CHECK(fprintf(fp, "%s-%d\n", "second", 2) == 9);
                CHECK(fputc('X', fp) == 'X');
                CHECK(fflush(fp) == 0);
                CHECK(fgetpos(fp, &position) == 0);
                CHECK(fseek(fp, 0L, SEEK_SET) == 0);
                CHECK(ftell(fp) == 0L);
                CHECK(fgets(line, sizeof line, fp) == line);
                CHECK(strcmp(line, "first\n") == 0);
                CHECK(fgets(line, sizeof line, fp) == line);
                CHECK(strcmp(line, "second-2\n") == 0);
                CHECK(getc(fp) == 'X');
                CHECK(ungetc('Y', fp) == 'Y');
                CHECK(getc(fp) == 'Y');
                CHECK(feof(fp) == 0);
                CHECK(getc(fp) == EOF);
                CHECK(feof(fp) != 0);
                clearerr(fp);
                CHECK(feof(fp) == 0 && ferror(fp) == 0);
                CHECK(fread(line, 1, 1, fp) == 0);      /* still at end of file */
                CHECK(feof(fp) != 0);
                clearerr(fp);
                CHECK(fsetpos(fp, &position) == 0);
                CHECK(fwrite("abc", 1, 3, fp) == 3);
                CHECK(ftell(fp) == 19L);
                CHECK(fseek(fp, 0L, SEEK_END) == 0);
                CHECK(ftell(fp) == 19L);
                CHECK(fseek(fp, 0L, SEEK_SET) == 0);
                CHECK(fread(line, 1, 19, fp) == 19);
                CHECK(feof(fp) == 0);                   /* exactly consumed */
                CHECK(line[0] == 'f' && line[18] == 'c');
                rewind(fp);
                CHECK(ftell(fp) == 0L && feof(fp) == 0);
                CHECK(fread(line, 1, 5, fp) == 5);
                CHECK(memcmp(line, "first", 5) == 0);
                CHECK(fclose(fp) == 0);
            }

            /* A second stream: setbuf must be called before any I/O, and its array
             * must be at least BUFSIZ bytes (C99 7.19.5.5p2 with 7.19.5.6p3). */
            fp = tmpfile();
            if (fp != NULL) {
                static char buffer_storage[BUFSIZ];
                CHECK(sizeof buffer_storage >= (size_t)BUFSIZ);
                setbuf(fp, buffer_storage);
                CHECK(fputs("10 20 30\n", fp) >= 0);
                CHECK(fflush(fp) == 0);
                rewind(fp);
                CHECK(fscanf(fp, "%d %d %d", &int_a, &int_b, &consumed) == 3);
                CHECK(int_a == 10 && int_b == 20 && consumed == 30);
                CHECK(fclose(fp) == 0);
            }
        }
    {
    const char *name_a = "c99_stdio_tmp.txt";
    const char *name_b = "c99_stdio_tmp_renamed.txt";
    FILE *fp = fopen(name_a, "w");
    if (fp != NULL) {
    CHECK(fputs("data", fp) >= 0);
    CHECK(fclose(fp) == 0);
    CHECK(rename(name_a, name_b) == 0);
    fp = fopen(name_b, "r");
    CHECK(fp != NULL);
        }
    }
    return 0;
}
