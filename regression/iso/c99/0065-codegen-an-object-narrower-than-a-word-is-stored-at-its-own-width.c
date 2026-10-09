/* 0065: CHECK(d.after == 22); CHECK(d.tail == 33);
 *
 * An object narrower than a word is stored at its own width. A structure of
 * three bytes assigned from a call was written with one eight-byte store, so the
 * bytes past the object were overwritten: the field beside it read as the
 * object's own padding. The same shape stored a qualifier set over the field
 * that follows it in the specifier a declaration is built from, which is how
 * `typedef const unsigned long x;` stopped naming a type -- the compiler built by
 * this one then read `atomic_uintptr_t` as an opaque type and refused V's own C
 * at sync__Channel, a thing the host compiled.
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

typedef struct {
    unsigned char a;
    unsigned char b;
    unsigned char c;
} Three;

struct Holder {
    Three first;
    unsigned int after;
    unsigned short tail;
};

static Three make(unsigned char a, unsigned char b, unsigned char c)
{
    Three t;

    t.a = a;
    t.b = b;
    t.c = c;
    return t;
}

static Three const kFrozen = { 4, 5, 6 };

int main(void)
{
    struct Holder d;

    /* The three bytes of the object, and the two fields that follow it. */
    d.after = 22;
    d.tail = 33;
    d.first = make(1, 2, 3);
    CHECK(d.first.a == 1);
    CHECK(d.first.b == 2);
    CHECK(d.first.c == 3);
    CHECK(d.after == 22);
    CHECK(d.tail == 33);

    /* A const object is read at its own width too, and the field beside it
     * survives the read. */
    d.after = 22;
    d.tail = 33;
    d.first = kFrozen;
    CHECK(d.first.a == 4);
    CHECK(d.first.c == 6);
    CHECK(d.after == 22);
    CHECK(d.tail == 33);

    /* Three bytes in a register, handed back and forth. */
    CHECK(make(7, 8, 9).c == 9);
    return 0;
}
