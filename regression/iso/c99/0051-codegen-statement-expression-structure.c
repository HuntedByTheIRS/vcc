/* 0051: a statement expression whose value is a structure

V's own generated C writes `v_panic(({ ... ; string_plus_many(34, parts); }))` at
every panic of a message it builds in place, so a statement expression whose
value is an object of an aggregate type has to reach both the argument it is
handed over as and the object it is. The body's statements run in the order they
were written, in one scope, and the value expression is then written as the
object it is rather than left in a register, because a register holds a value
and an aggregate is the case that has no such register.

The three value expressions that matter: a name of the object's type, a call of
it, and a conditional of it. Each is compared against what gcc 16.2.1 makes of
the same program, which is the reference for a GNU statement expression.
*/

#include <stdio.h>

struct pair {
    long first;
    long second;
};

static struct pair make(long first, long second)
{
    struct pair p;
    p.first = first;
    p.second = second;
    return p;
}

static long add(struct pair p)
{
    return p.first + p.second;
}

static long from_a_name(void)
{
    /* The body declares the object and the value is that name. */
    return add(({ struct pair p = make(3, 4); p; }));
}

static long from_a_call(void)
{
    /* The value is a call, whose result arrives in registers for 16 bytes and
       in the caller's storage past that. */
    return add(({ struct pair p = make(5, 6); make(p.first + 1, p.second); }));
}

static long from_a_conditional(int which)
{
    return add(({ struct pair p = { 7, 8 }; struct pair q = { 9, 10 }; which ? p : q; }));
}

static long body_runs_in_order(void)
{
    /* Every statement of the body runs, including the ones after the assignment
       that names the value. */
    return add(({ struct pair p = { 20, 0 }; p.second = 1; p.second += 1; p; }));
}

/* A statement expression of a structure larger than two eightbytes: the value
   expression is a call whose result the callee writes into the storage the
   caller lent it, and that storage is what the argument is copied from. */
struct wide {
    long a;
    long b;
    long c;
};

static struct wide wide_make(long base)
{
    struct wide w;
    w.a = base;
    w.b = base + 1;
    w.c = base + 2;
    return w;
}

static long wide_add(struct wide w)
{
    return w.a + w.b + w.c;
}

static long from_a_wide_call(void)
{
    return wide_add(({ struct wide w = wide_make(1); wide_make(w.a + 3); }));
}

/* The value expression of a statement expression can itself be one, and the
   inner body's names are not visible outside it. */
static long nested(void)
{
    return add(({ struct pair p = ({ struct pair q = make(11, 12); q; }); p; }));
}

int main(void)
{
    long a = from_a_name();
    long b = from_a_call();
    long c = from_a_conditional(1);
    long d = from_a_conditional(0);
    long e = body_runs_in_order();
    long f = from_a_wide_call();
    long g = nested();
    printf("%ld %ld %ld %ld %ld %ld %ld\n", a, b, c, d, e, f, g);
    return a == 7 && b == 12 && c == 15 && d == 19 && e == 22 && f == 15 && g == 23 ? 0 : 1;
}
