/* 950: CHECK(n == 3);
 *
 * not in monolithic.c: added after the corpus was split, so it has no line there.
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
    FILE *fp = fopen("c99_950_fprintf.txt", "w");
    int n;
    if (fp == 0) { return 1; }
    n = fprintf(fp, "%s", "abc");
    fclose(fp);
    CHECK(n == 3);
    return 0;
}
