/* 0052: an element of an aggregate type is stored as an object

An element of an array of structures is storage, so `a[i] = v` is the object copy
an assignment between two objects makes: the bytes of the source move into the
element and neither side is read as a value. The machine moves a byte, two, four
and eight, so a structure of sixteen or twenty-four bytes has no instruction to
be read or written with, and a path that reads the element as a value refuses the
program instead of copying it.

Both arrays a program reaches an element of are here, because they are two paths
in the emitter: a top-level array, whose element is at an address the image
holds, and an array of a frame, whose element is at an offset from the frame
pointer. The source is every shape the copy takes: a structure, an element of
another array, a member of a structure, a call and a conditional. The values are
read back through a function that takes the structure by value, so a copy that
wrote the wrong bytes is a wrong sum and not a wrong constant.

Measured on gcc 16.2.1 at -std=c99, which exits 0 and prints the same numbers.
*/


struct pair {
    long first;
    long second;
};

struct triple {
    long a;
    long b;
    long c;
};

struct holder {
    struct pair inner;
    int tag;
};

static struct pair make_pair(long first, long second)
{
    struct pair p;
    p.first = first;
    p.second = second;
    return p;
}

static struct triple make_triple(long base)
{
    struct triple t;
    t.a = base;
    t.b = base + 1;
    t.c = base + 2;
    return t;
}

static long pair_sum(struct pair p)
{
    return p.first + p.second;
}

static long triple_sum(struct triple t)
{
    return t.a + t.b + t.c;
}

/* Sixteen bytes: two eightbytes, the size a machine moves in two registers. */
static struct pair pairs[4];
static struct triple triples[4];

static long globals(void)
{
    struct pair local = { 3, 4 };
    struct holder h;
    int flag = 1;
    h.inner.first = 5;
    h.inner.second = 6;
    pairs[1] = local;                 /* a name into an element */
    pairs[2] = pairs[1];              /* an element into an element */
    pairs[3] = h.inner;               /* a member into an element */
    pairs[0] = make_pair(1, 2);       /* a call into an element */
    local = pairs[3];                 /* an element into a name */
    triples[1] = make_triple(7);      /* twenty-four bytes through the same path */
    triples[2] = triples[1];
    triples[3] = flag ? triples[1] : triples[2];
    return pair_sum(pairs[0]) + pair_sum(pairs[1]) + pair_sum(pairs[2])
        + pair_sum(pairs[3]) + triple_sum(triples[1]) + triple_sum(triples[2])
        + triple_sum(triples[3]);
}

/* The same four stores into an array of a frame rather than one of the image. */
static long locals(void)
{
    struct pair local[4];
    struct pair value = { 30, 40 };
    struct triple trip[2];
    struct holder h;
    h.inner.first = 50;
    h.inner.second = 60;
    local[1] = value;
    local[2] = local[1];
    local[3] = h.inner;
    local[0] = make_pair(10, 20);
    trip[1] = make_triple(70);
    trip[0] = trip[1];
    return pair_sum(local[0]) + pair_sum(local[1]) + pair_sum(local[2])
        + pair_sum(local[3]) + triple_sum(trip[0]) + triple_sum(trip[1]);
}

/* An element written behind two subscripts, and one reached through a pointer to
   the array, which are the same address computed twice. */
static long reached_twice(void)
{
    struct pair rows[2][2];
    struct pair *p;
    struct pair value = { 100, 200 };
    rows[1][1] = value;
    p = rows[0];
    p[0] = rows[1][1];
    return pair_sum(rows[1][1]) + pair_sum(p[0]);
}

int main(void)
{
    long g = globals();
    long l = locals();
    long r = reached_twice();
    return g == 100 && l == 706 && r == 600 ? 0 : 1;
}
