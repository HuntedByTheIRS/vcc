/* 0050: a float an address points at is read and written as a float

The four-byte floating type had a path of its own everywhere a float is stored
in an object whose name the back end knows: a local, a member, an element of a
named array, an argument, a return. Where the object had to be reached through
an address the type fell to the reader that sizes the pointed-at type, and a
float has no integer width, so `*(const float *)a` was refused with
`* reads through an address of const float, and this back end reads ints, chars,
doubles and pointers only`, `*p = v` for a `float *p` with the matching message
for a store, and `a[i] = v` for an array the subscript reached through a pointer
with `an element of float is not one this back end stores`.

The three sites now take the single-precision instruction the machine has,
which is what a float local already used: load_float_indirect in emit_deref,
assign_single_at for a write through an address, and the same store for an
element reached through a pointer. The value stays in the floating accumulator
and the width travels with it, so a float read this way is a float and not the
four bytes read as an int.

Measured on gcc 16.2.1: every value printed here is the same under gcc and under
vcc, and the pre-change binary refuses the file at its first line. */


struct P { float x; float y; };

static float read_through(const float *p)
{
    return *p;
}

static void write_through(float *p, float v)
{
    *p = v;
}

static void write_element(float *a, int i, float v)
{
    a[i] = v;
}

static float read_element(const float *a, int i)
{
    return a[i];
}

int main(void)
{
    float v = 1.5f;
    float a[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
    const float *cp = &v;

    /* Through an address of a const float, which is the shape V's own generated
       C does in its array-sort comparators. */
    if (read_through(cp) != 1.5f) {
        return 1;
    }

    /* Written through an address, with the value converted from an int. */
    write_through(&a[1], 2.25f);
    if (a[1] != 2.25f) {
        return 1;
    }
    write_through(&a[2], -3.5f);
    if (a[2] != -3.5f) {
        return 1;
    }

    /* An element at a computed address, both ways. */
    write_element(a, 3, 7.5f);
    if (read_element(a, 3) != 7.5f) {
        return 1;
    }
    if (read_element(a, 1) != 2.25f) {
        return 1;
    }

    /* A cast to a const float pointer, and a member reached through one. */
    const struct P *pp = (const struct P *)&a[0];
    if (pp->y != 2.25f) {
        return 1;
    }

    /* The value is a float and not four bytes read as an int: the two differ in
       the low byte here. */
    float small = 1.0e-40f;
    if (read_through(&small) != small) {
        return 1;
    }

    return 0;
}
