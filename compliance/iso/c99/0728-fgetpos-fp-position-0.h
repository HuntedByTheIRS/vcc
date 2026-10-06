/* 0728: CHECK(fgetpos(fp, &position) == 0);
 *
 * monolithic.c:11558 (stdio)
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
    {
    FILE *fp = tmpfile();
    fpos_t position;
    if (fp != NULL) {
    CHECK(fputs("first\n", fp) >= 0);
    CHECK(fprintf(fp, "%s-%d\n", "second", 2) == 9);
    CHECK(fputc('X', fp) == 'X');
    CHECK(fflush(fp) == 0);
    CHECK(fgetpos(fp, &position) == 0);
        }
    }
    return 0;
}
