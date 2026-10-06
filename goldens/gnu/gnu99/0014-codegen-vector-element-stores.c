/* a vector type declared with __attribute__((vector_size(N))) */

#include <stdio.h>

typedef int v4si __attribute__((vector_size(16)));
typedef short v8hi __attribute__((vector_size(16)));
typedef unsigned char v16qi __attribute__((vector_size(16)));

int main(void)
{
    v4si a = { 1, 2, 3, 4 };
    v4si b = { 10, 20, 30, 40 };
    v4si c = a + b;
    int i;

    printf("%zu %zu %zu\n", sizeof(v4si), sizeof(v8hi), sizeof(v16qi));
    printf("%zu %zu %zu\n", (size_t)__alignof__(v4si), (size_t)__alignof__(v8hi),
           (size_t)__alignof__(v16qi));
    for (i = 0; i < 4; i++) printf("%d%s", c[i], i == 3 ? "\n" : " ");
    c[1] = 99;
    printf("%d %d\n", c[0], c[1]);
    return 0;
}
