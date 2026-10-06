/* __builtin_alloca hands back storage that is aligned and lives to the block end */

#include <stdio.h>

static int fill(char *p, int n, int seed)
{
    int i, sum = 0;
    for (i = 0; i < n; i++) {
        p[i] = (char)(seed + i);
        sum += p[i];
    }
    return sum;
}

int main(void)
{
    int i;
    for (i = 1; i <= 3; i++) {
        char *p = __builtin_alloca((unsigned)i * 4);
        char *q = __builtin_alloca((unsigned)i * 4);
        printf("%d %d %d\n", ((unsigned long)p & 15u) == 0, fill(p, i * 4, i),
               fill(q, i * 4, i + 1));
    }
    return 0;
}
