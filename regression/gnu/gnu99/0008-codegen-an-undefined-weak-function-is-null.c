/* 0008: an undefined weak function is the null address

The weak attribute (GCC 6.4.1) on a declaration this file has no definition for
is an import a link does not have to answer: ELF gives an undefined weak symbol
the value zero, so a program that asks whether the name is there before calling
it links and runs where nothing defines it. The emitter recorded the attribute
on a definition only, so `hook` reached the unresolved-import check as a plain
import and the compile stopped at

    vcc: undefined reference to `hook': no library the image names defines it

for a file gcc linked and ran to exit 0. Fixed by "codegen, backend: an
undefined weak declaration is a weak import".

The shape below is the one that caught it: the address of a name declared weak
with nothing behind it, and the call a program makes through it once it has
asked. The second half is the line the fix must not cross, a weak prototype
whose definition is in the same file: that name is defined, weak or not, and
its address is not zero.

The case prints nothing on purpose: for a regression case a line of output is
itself the regression, so each check returns non-zero and writes one line
saying which one failed. A build failure is the other way this case fails, and
the one the defect took. */

#include <stdio.h>

extern int hook(void) __attribute__((weak));

int present(void) __attribute__((weak));
int present(void) { return 3; }

/* Never called, and it has to be compiled anyway: the call to a name with
   nothing behind it is a reference the linker fills with the address zero, and
   a program that calls it without asking runs there. The reference compiling
   is what this function is here for. */
static int call_it(void) { return hook(); }

int main(void)
{
    if (hook != 0) {
        fprintf(stderr, "the address of an undefined weak function was not null\n");
        return 1;
    }
    if (present == 0) {
        fprintf(stderr, "a weak function this file defines has no address\n");
        return 1;
    }
    if (present() != 3) {
        fprintf(stderr, "a weak function this file defines returned %d\n", present());
        return 1;
    }
    return 0;
}
