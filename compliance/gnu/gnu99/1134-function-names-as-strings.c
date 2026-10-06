/* 1134: function-names-as-strings
 *
 * GCC 6.12.24 Function Names as Strings: "__FUNCTION__ is another name for
 * __func__ ... In C, __PRETTY_FUNCTION__ is yet another name for __func__,
 * except that at file scope ... it evaluates to the string "top level".
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

static const char *const top_level = __PRETTY_FUNCTION__;

static int name_is(const char *got, const char *want)
{
    return strcmp(got, want) == 0;
}

int main(void)
{
    CHECK(name_is(__FUNCTION__, "main"));
    CHECK(name_is(__PRETTY_FUNCTION__, "main"));
    CHECK(name_is(top_level, "top level"));
    return 0;
}
