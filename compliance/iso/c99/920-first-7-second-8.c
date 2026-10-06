/* 920: CHECK(first == 7 && second == 8);
 *
 * monolithic.c:12190 (stdio-redirect)
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
    const char *input_name = "c99_stdio_input.txt";
    int first = 0, second = 0;
    FILE *file;
    file = fopen(input_name, "w");
    if (file != NULL) {
    fputs("7 8\nZ\n", file);
    fclose(file);
    if (freopen(input_name, "r", stdin) != NULL) {
    CHECK(scanf("%d %d", &first, &second) == 2);
    CHECK(first == 7 && second == 8);
        }
    }
    return 0;
}
