/* 1150: an-asm-goto-that-jumps-to-a-c-label
 *
 * GCC 6.11.2 Extended Asm - Assembler Instructions with C Expression Operands:
 * "With extended asm you can read and write C variables from assembler and
 * perform jumps from assembler code to C labels. ... asm asm-qualifiers
 * (AssemblerTemplate : OutputOperands : InputOperands : Clobbers : GotoLabels)"
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    int reached = 0;

    asm goto("jmp %l0" :::: target);
    reached = 2;
target:
    reached += 1;
    CHECK(reached == 1);
    return 0;
}
