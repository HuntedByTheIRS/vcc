/* 727: CHECK(fflush(fp) == 0);
 *
 * monolithic.c:11557 (stdio)
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
    if (fp != NULL) {
    CHECK(fputs("first\n", fp) >= 0);
    CHECK(fprintf(fp, "%s-%d\n", "second", 2) == 9);
    CHECK(fputc('X', fp) == 'X');
    CHECK(fflush(fp) == 0);
        }
    }
    return 0;
}
