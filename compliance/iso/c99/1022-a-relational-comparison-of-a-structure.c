/* 1022: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.5.8p2: both operands of a relational operator shall
 * have real type or shall be pointers to compatible object types.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

struct S { int a; };

int main(void)
{
    struct S s = {1};
    return s < s;
}
