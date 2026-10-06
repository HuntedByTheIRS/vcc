/* 1053: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.8.5p2: the controlling expression of an iteration
 * statement shall have scalar type.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

struct S { int a; };

int main(void)
{
    struct S s = {1};
    while (s)
        return 1;
    return 0;
}
