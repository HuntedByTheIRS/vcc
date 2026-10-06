/* 0907: CHECK(strerror(EILSEQ) != NULL);
 *
 * monolithic.c:12072 (runtime)
 */

#include <stdio.h>
#include <errno.h>
#include <stddef.h>
#include <string.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    errno = 0;
    CHECK(errno == 0);
    errno = EDOM;
    CHECK(errno == EDOM);
    errno = ERANGE;
    CHECK(errno == ERANGE);
    errno = EILSEQ;
    CHECK(errno == EILSEQ);
    CHECK(EDOM != ERANGE && ERANGE != EILSEQ);
    CHECK(strerror(EILSEQ) != NULL);
    return 0;
}
