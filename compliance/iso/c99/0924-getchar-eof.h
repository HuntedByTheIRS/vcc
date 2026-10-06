/* 0924: CHECK(getchar() == EOF);
 *
 * monolithic.c:12194 (stdio-redirect)
 */

#include <stdio.h>

static int g_fail;

static int g_section_checks;

static void sec_begin(const char *title)
{
    if (g_section_checks != 0) {
        printf("    (%d checks)\n", g_section_checks);
    }
    g_section_checks = 0;
    printf("[%s]\n", title);
}

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
    const char *output_name = "c99_stdio_output.txt";
    int failures = g_fail;
    int first = 0, second = 0;
    char line[16];
    FILE *file;
    file = fopen(input_name, "w");
    if (file != NULL) {
    fputs("7 8\nZ\n", file);
    fclose(file);
    if (freopen(input_name, "r", stdin) != NULL) {
    sec_begin("15b stdin redirected with freopen");
    CHECK(scanf("%d %d", &first, &second) == 2);
    CHECK(first == 7 && second == 8);
    CHECK(getchar() == '\n');
    CHECK(getchar() == 'Z');
    CHECK(getchar() == '\n');
    CHECK(getchar() == EOF);
    CHECK(feof(stdin) != 0);
    clearerr(stdin);
    CHECK(fgets(line, sizeof line, stdin) == NULL);
        }
    }
    return 0;
}
