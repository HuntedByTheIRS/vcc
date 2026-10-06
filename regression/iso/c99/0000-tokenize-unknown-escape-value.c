/* 0000: an escape gcc does not know is the character itself

A backslash before a character with no meaning in an escape sequence is
undefined by C99 6.4.4.4; gcc takes the character itself, and the parser used
to refuse it.  Fixed in 3d0811c ("parser: an escape gcc does not know is the
character itself"). */

#include <stdio.h>

int main(void)
{
    if ('\q' != 'q') { fprintf(stderr, "an escape with no meaning is not the character itself\n"); return 1; }
    if ('\x41' != 'A' || '\101' != 'A') { fprintf(stderr, "a standard escape lost its value\n"); return 1; }
    return 0;
}
