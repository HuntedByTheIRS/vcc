/* 0000: a cleanup object's call runs while the object is still in scope

The cleanup attribute (GCC 6.4.1) runs its function where the block the object
was declared in ends. The emitter kept every block's pending calls on one stack
and never gave a block's entry back when the block closed, so a call for an
object of an inner block ran again at the next exit and named an object that no
longer had storage. Found while implementing 1140 and fixed with it
("ast, parser, codegen: the cleanup attribute runs its function where a block
ends").

The shape below is the one that caught it: an inner block's object, and a return
after the block. */

#include <stdio.h>

static int seen[4];
static int count;

static void note(int *p) { seen[count++] = *p; }

static int body(void)
{
    __attribute__((cleanup(note))) int outer = 1;
    {
        __attribute__((cleanup(note))) int inner = 2;
        (void)inner;
    }
    return outer;
}

int main(void)
{
    int answer = body();

    if (answer != 1) { fprintf(stderr, "the object was not returned\n"); return 1; }
    if (count != 2 || seen[0] != 2 || seen[1] != 1) {
        fprintf(stderr, "the cleanups ran %d time(s) as %d, %d\n", count, seen[0], seen[1]);
        return 1;
    }
    return 0;
}
