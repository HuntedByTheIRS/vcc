/* 0058: an array declared without a size and then defined with one

C99 6.2.7p2 makes two array types compatible when one of them has a size and the
other does not, and p3 makes the composite type the one that has the size, so a
declaration of `int a[]` and a declaration of `int a[3]` describe one object of
three elements whichever of the two wrote the size. The sized declaration was
refused as "a constraint violation: a is declared as int[] in this scope and
this declaration gives it int[3], and two declarations of one name in one scope
have to describe one type" because an incomplete array and a sized one were
compared as two different types. The two are now compared by the rule the
standard gives them, and the name keeps the composite type, in
redeclaration_conflicts and declare_name (parser/declarations.v). */

extern int ext_after[];
int ext_after[3] = {7, 8, 9};

int ext_before[3] = {1, 2, 3};
extern int ext_before[];

int main(void)
{
    /* The object is int[3] and its name is the address of its first element,
       whichever order the two declarations were written in. */
    if (ext_after[1] != 8) { return 1; }
    if (ext_before[1] != 2) { return 2; }
    /* sizeof reads the composite type, so the size the definition gave is not
       lost to the declaration that wrote none. */
    if (sizeof(ext_after) != 3 * sizeof(int)) { return 3; }
    if (sizeof(ext_before) != 3 * sizeof(int)) { return 4; }
    return 0;
}
