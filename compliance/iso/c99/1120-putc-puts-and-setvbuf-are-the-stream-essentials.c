/* 1120: putc-puts-and-setvbuf-are-the-stream-essentials
 *
 * ISO/IEC 9899:1999 7.19.7.8: the putc function writes the character c to
 * the output stream pointed to by stream.
 */

#include <stdio.h>
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
    FILE *f = tmpfile();
    char buf[16];
    char io[16];
    if (!f)
        return 1;
    CHECK(putc('a', f) == 'a');
    CHECK(puts("") >= 0);
    CHECK(setvbuf(f, io, _IOFBF, sizeof io) == 0);
    CHECK(fputc('b', f) == 'b');
    rewind(f);
    CHECK(fgets(buf, sizeof buf, f) != NULL);
    CHECK(strcmp(buf, "ab") == 0);
    fclose(f);
    return 0;
}
