/* 0002: stringize writes the argument the way it was spelled

#__VA_ARGS__ used to normalize the spacing of every argument, so S(1, 2, 3)
and S(1,2,3) both came back without a space after the comma.  The token
carries whether whitespace preceded it now.  Fixed in f049f87 ("preprocess:
stringize writes the argument the way it was spelled"). */

#include <stdio.h>
#include <string.h>

#define S(...) #__VA_ARGS__
int main(void)
{
    if (strcmp(S(1, 2, 3), "1, 2, 3") != 0) { fprintf(stderr, "stringize lost the argument spacing\n"); return 1; }
    if (strcmp(S(1,2,3), "1,2,3") != 0) { fprintf(stderr, "stringize added spacing that was not spelled\n"); return 1; }
    return 0;
}
