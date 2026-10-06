/* 0951: CHECK(first == 'x' && second == 'y');
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
    FILE *fp = fopen("c99_951_ungetc.txt", "w");
    int first, second;
    if (fp == 0) { return 1; }
    fputs("ab", fp);
    fclose(fp);
    fp = fopen("c99_951_ungetc.txt", "r");
    if (fp == 0) { return 2; }
    CHECK(ungetc('y', fp) == 'y');
    CHECK(ungetc('x', fp) == 'x');
    first = getc(fp);
    second = getc(fp);
    CHECK(first == 'x');
    CHECK(second == 'y');
    fclose(fp);
    return 0;
}
