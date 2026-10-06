/* 1017: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.5.4p2: unless the type name specifies a void type,
 * the type name shall specify qualified or unqualified scalar type and the
 * operand shall have scalar type.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

struct S { int a; };

int main(void)
{
    struct S s = {1};
    return (int)s;
}
