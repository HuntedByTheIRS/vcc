#include <stdio.h>

#define SQUARE(x) ((x) * (x))
#define STR(x) #x
#define XSTR(x) STR(x)
#define CAT(a, b) a##b
#define PI 3.14159
#define AREA(r) (PI * (r) * (r))
#define VALUE 42

int main(void) {
    printf("%d\n", SQUARE(3));
    printf("%s\n", STR(hello));
    printf("%s\n", XSTR(VALUE));
    int CAT(foo, bar) = 7;
    printf("%d\n", foobar);
    printf("%.5f\n", AREA(2.0));
    return 0;
}
