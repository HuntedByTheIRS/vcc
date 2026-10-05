/* 691: CHECK(snprintf(formatted, sizeof formatted, "%Lf", 1.5L) == 8);
 *
 * monolithic.c:11499 (stdio)
 */

#include <stdio.h>
#include <inttypes.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

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
    double d = 3.14159;
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
    return 0;
}
