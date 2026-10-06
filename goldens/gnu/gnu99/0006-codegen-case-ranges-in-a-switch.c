/* a case label that names a range of values */

#include <stdio.h>

static const char *kind(int c)
{
    switch (c) {
    case 'a' ... 'z': return "lower";
    case 'A' ... 'Z': return "upper";
    case '0' ... '9': return "digit";
    }
    return "other";
}

int main(void)
{
    printf("%s %s %s %s\n", kind('q'), kind('Q'), kind('7'), kind('?'));
    printf("%s %s\n", kind('a'), kind('z'));
    return 0;
}
