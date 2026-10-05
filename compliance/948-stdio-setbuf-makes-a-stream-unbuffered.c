/* 948: CHECK(strcmp(got, "hi") == 0);
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
    char got[8];
    FILE *fp = fopen("c99_948_setbuf.txt", "w");
    if (fp == 0) { return 1; }
    setbuf(fp, 0);
    fputs("hi", fp);
    fclose(fp);
    fp = fopen("c99_948_setbuf.txt", "r");
    if (fp == 0) { return 2; }
    setbuf(fp, 0);
    if (fgets(got, sizeof got, fp) == 0) { return 3; }
    fclose(fp);
    CHECK(strcmp(got, "hi") == 0);
    return 0;
}
