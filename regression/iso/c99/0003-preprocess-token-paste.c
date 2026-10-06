/* 0003: the ## operator joins tokens before rescanning

A pasted name has to expand, and the argument of a pasted macro has to expand
first through a second macro.  Pinned by 3347f71 ("preprocess: test the
paste, stringize and conditional rules"). */

#include <stdio.h>
#include <string.h>

#define CAT(a, b) a##b
#define STR(x) #x
#define XSTR(x) STR(x)
#define VAL 42
int main(void)
{
    int CAT(x, y) = 6;
    if (xy != 6) { fprintf(stderr, "token paste did not make the name\n"); return 1; }
    if (strcmp(XSTR(VAL), "42") != 0) { fprintf(stderr, "a pasted argument did not expand\n"); return 1; }
    return 0;
}
