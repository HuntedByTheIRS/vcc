#include <stdio.h>

int main(void) {
    char nl = '\n';
    char tab = '\t';
    char bs = '\\';
    char sq = '\'';
    char dq = '\"';
    char nul = '\0';
    char hexc = '\x41';
    char octc = '\101';
    const char *s = "a\tb\nc\\d\"e";
    const char *cat = "one" " two" " three";
    printf("%d %d %d %d %d %d\n", nl, tab, bs, sq, dq, nul);
    printf("%c%c\n", hexc, octc);
    printf("%s\n", s);
    printf("%s\n", cat);
    printf("%zu %zu\n", sizeof("\x41"), sizeof("ab" "cd"));
    return 0;
}
