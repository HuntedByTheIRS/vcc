/* 953: CHECK(strcmp(line, "other") == 0);
 *
 * not in monolithic.c: added after the corpus was split, so it has no line there.
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
    char line[16];
    FILE *fp = fopen("c99_953_rewind.txt", "w");
    if (fp == 0) { return 1; }
    fputs("first", fp);
    rewind(fp);
    fputs("other", fp);
    fclose(fp);
    fp = fopen("c99_953_rewind.txt", "r");
    if (fp == 0) { return 2; }
    if (fgets(line, sizeof line, fp) == 0) { return 3; }
    fclose(fp);
    /* Writing from the start of the stream overwrote what was there, which is
     * what says the position really moved back. */
    CHECK(strcmp(line, "other") == 0);
    return 0;
}
