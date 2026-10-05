/* 952: CHECK(memcmp(wrote, read, sizeof wrote) == 0);
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

struct c99_pair {
    int a;
    int b;
};

int main(void)
{
    struct c99_pair wrote[3];
    struct c99_pair read[3];
    FILE *fp;
    int i;
    for (i = 0; i < 3; i++) {
        wrote[i].a = i;
        wrote[i].b = i * 10;
    }
    fp = fopen("c99_952_fwrite.bin", "wb");
    if (fp == 0) { return 1; }
    CHECK(fwrite(wrote, sizeof(struct c99_pair), 3, fp) == 3);
    fclose(fp);
    fp = fopen("c99_952_fwrite.bin", "rb");
    if (fp == 0) { return 2; }
    CHECK(fread(read, sizeof(struct c99_pair), 3, fp) == 3);
    fclose(fp);
    CHECK(memcmp(wrote, read, sizeof read) == 0);
    return 0;
}
