/* a structure with no members, and one that holds it */

#include <stdio.h>

struct empty {};

struct with_empty { int a; struct empty b; };

int main(void)
{
    struct empty e;

    printf("%zu %zu %zu\n", sizeof(struct empty), sizeof(e), sizeof(struct with_empty));
    return 0;
}
