#include <stdio.h>

struct Pair {
    int a, b;
};

struct Big {
    long x, y, z;
};

static int many(int a, int b, int c, int d, int e, int f, int g, int h) {
    return a + b + c + d + e + f + g + h;
}

static struct Pair swap(struct Pair p) {
    struct Pair q;
    q.a = p.b;
    q.b = p.a;
    return q;
}

static struct Big scale(struct Big v, long k) {
    struct Big r;
    r.x = v.x * k;
    r.y = v.y * k;
    r.z = v.z * k;
    return r;
}

static int twice(int x) {
    return x * 2;
}

static int apply(int (*f)(int), int x) {
    return f(x);
}

int main(void) {
    printf("%d\n", many(1, 2, 3, 4, 5, 6, 7, 8));
    struct Pair p = {10, 20};
    struct Pair q = swap(p);
    printf("%d %d\n", q.a, q.b);
    struct Big b = {1, 2, 3};
    struct Big s = scale(b, 10);
    printf("%ld %ld %ld\n", s.x, s.y, s.z);
    printf("%d\n", apply(twice, 21));
    return 0;
}
