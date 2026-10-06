/* 1124: tmpnam-and-tmpfile-name-and-open-a-temporary-file
 *
 * ISO/IEC 9899:1999 7.19.4.4: the tmpnam function generates a string that
 * is a valid file name and that is not the same as the name of an existing
 * file.
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
    char name[L_tmpnam];
    FILE *f;
    CHECK(tmpnam(name) != NULL);
    CHECK(name[0] != '\0');
    CHECK(tmpfile() != NULL);
    f = tmpfile();
    CHECK(f != NULL);
    fclose(f);
    return 0;
}
