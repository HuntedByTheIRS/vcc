/* 0051: a tentative definition of an array with no size takes one element

C99 6.9.2p2 completes a tentative definition whose array type has no size to an
array of one element at the end of the translation unit when nothing else
defines the name, and gives it a definition with an initializer of zero. `int
ext_arr[];` is therefore an object one int wide with a real address, and a later
declaration that writes a size is the composite type the name takes instead. The
object was laid out with no size at all, so its name read as the value nil and a
comparison against zero found it equal: `!(ext_arr != 0)` failed and
`printf("%p", (void *)ext_arr)` printed `(nil)`. The name is now completed at the
end of the file and storage is given to it, in complete_tentative_arrays
(parser/parser.v). */

int ext_arr[];
int *p = ext_arr;

int sized[];
int sized[3];

int from_extern[];
extern int from_extern[2];

int main(void)
{
    /* A tentative definition with no size is a real object, not a null name. */
    if (ext_arr == 0) { return 1; }
    if (p != ext_arr) { return 2; }
    /* A later declaration that writes a size is what the name is: the object
       keeps three elements and sizeof reads them. */
    if (sized[0] != 0 || sized[2] != 0) { return 3; }
    if (sizeof(sized) != 3 * sizeof(int)) { return 4; }
    /* A later extern declaration sizes the object the tentative definition
       creates, so it has storage and the size the extern wrote. */
    if (from_extern == 0) { return 5; }
    if (sizeof(from_extern) != 2 * sizeof(int)) { return 6; }
    return 0;
}
