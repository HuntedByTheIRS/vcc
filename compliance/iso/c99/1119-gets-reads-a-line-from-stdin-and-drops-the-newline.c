/* 1119: gets-reads-a-line-from-stdin-and-drops-the-newline
 *
 * ISO/IEC 9899:1999 7.19.7.7: the gets function reads characters from the
 * input stream pointed to by stdin into the array pointed to by s until
 * end-of-file or a newline.
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
    FILE *f = fopen("gets_input.txt", "w");
    char buf[16];
    if (!f)
        return 1;
    fputs("hi\n", f);
    fclose(f);
    if (freopen("gets_input.txt", "r", stdin) == NULL)
        return 1;
    CHECK(gets(buf) != NULL);
    CHECK(strcmp(buf, "hi") == 0);
    return 0;
}
