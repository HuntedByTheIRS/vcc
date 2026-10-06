/* 0731: CHECK(fgets(line, sizeof line, fp) == line);
 *
 * monolithic.c:11561 (stdio)
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
    CHECK(SEEK_SET == 0 && SEEK_CUR == 1 && SEEK_END == 2);
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
        }
    }
    return 0;
}
