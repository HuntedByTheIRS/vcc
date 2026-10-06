/* __func__, __FUNCTION__ and __PRETTY_FUNCTION__ as strings */

#include <stdio.h>

static const char *top = __PRETTY_FUNCTION__;

static void three(void)
{
    printf("%s|%s|%s\n", __FUNCTION__, __PRETTY_FUNCTION__, __func__);
}

int main(void)
{
    printf("%s\n", top);
    three();
    return 0;
}
