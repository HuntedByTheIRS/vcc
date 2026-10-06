/* 0928: CHECK(strcmp(__FILE__, "c99-line-directive.h") == 0);
 *
 * monolithic.c:12329 (line)
 */

#include <stdio.h>
#include <stddef.h>
#include <string.h>

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
    sec_begin("19 #line directive");
    #line 4242 "c99-line-directive.h"
    CHECK(__LINE__ == 4242);
    CHECK(strcmp(__FILE__, "c99-line-directive.h") == 0);
    #line 7
    CHECK(__LINE__ == 7);
    CHECK(strcmp(__FILE__, "c99-line-directive.h") == 0);
    #line 1 "monolithic.c"
    CHECK(__LINE__ == 1);
    CHECK(strcmp(__FILE__, "monolithic.c") == 0);
    return 0;
}
