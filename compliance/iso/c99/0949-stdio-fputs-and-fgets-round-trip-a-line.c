/* 0949: CHECK(strcmp(line, "first") == 0);
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
    char line[32];
    FILE *fp = fopen("c99_949_fgets.txt", "w");
    if (fp == 0) { return 1; }
    fputs("first\nsecond\n", fp);
    fclose(fp);
    fp = fopen("c99_949_fgets.txt", "r");
    if (fp == 0) { return 2; }
    if (fgets(line, sizeof line, fp) == 0) { return 3; }
    CHECK(strcmp(line, "first\n") == 0);
    if (fgets(line, sizeof line, fp) == 0) { return 4; }
    CHECK(strcmp(line, "second\n") == 0);
    fclose(fp);
    return 0;
}
