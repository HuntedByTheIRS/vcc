/* the cleanup attribute runs its function where the scope ends */

#include <stdio.h>

static int seen[12];
static int count;

static void note(int *p) { seen[count++] = *p; }

static void report(const char *what)
{
    int i;
    printf("%s:", what);
    for (i = 0; i < count; i++) printf(" %d", seen[i]);
    printf("\n");
    count = 0;
}

static int blocks(void)
{
    __attribute__((cleanup(note))) int a = 1;
    __attribute__((cleanup(note))) int b = 2;
    { __attribute__((cleanup(note))) int c = 3; }
    return a + b;
}

static int broken_out(void)
{
    int i;
    for (i = 0; i < 5; i++) {
        __attribute__((cleanup(note))) int k = 10 + i;
        if (i == 2) break;
    }
    return i;
}

static int jumped_over(int n)
{
    if (n == 0) {
        __attribute__((cleanup(note))) int z = 20;
        goto out;
    }
    return 1;
out:
    return 0;
}

static double gave_back(void)
{
    __attribute__((cleanup(note))) int pad = 30;
    return 2.5;
}

int main(void)
{
    printf("blocks=%d\n", blocks());
    report("blocks");
    printf("break=%d\n", broken_out());
    report("break");
    printf("goto=%d\n", jumped_over(0));
    report("goto");
    printf("return=%g\n", gave_back());
    report("return");
    return 0;
}
