/* 0059: an extern declaration of an array with no size inside a body

C99 6.7.2.1p4-5 lets an array be declared with no size wherever a declaration
may appear, and makes the array types compatible when one has a size and the
other does not. An `extern int ext_arr[];` written inside a body is a second
declaration of the object declared outside it (6.2.2, 6.2.7), whose composite
type is the sized one, and it gives the body no storage of its own. It was
refused as "an array declaration in a body needs a size that is a number and
more than zero". An array declaration in a body that is extern now keeps its
incomplete type and takes the object's own size, in the declaration reader in
parser/statements.v. */

int ext_arr[3] = {7, 8, 9};

int main(void)
{
    extern int ext_arr[];
    /* The inner declaration adds no storage: the name reaches the object the
       file defined, and reads the values it was defined with. */
    if (ext_arr[0] != 7 || ext_arr[2] != 9) { return 1; }
    /* The composite type is the object's own, so the size is the definition's
       and not the brackets that wrote none. */
    if (sizeof(ext_arr) != 3 * sizeof(int)) { return 2; }
    return 0;
}
