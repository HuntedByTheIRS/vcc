/* 0965: CHECK(memcmp(&copy, &source, sizeof source) == 0);
 *
 * not in monolithic.c: added after the corpus was split, so it has no line there.
 */

#include <stdio.h>
#include <string.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

struct c99_padded {
    char c;
    int i;
};

int main(void)
{
    struct c99_padded source;
    struct c99_padded copy;
    memset(&source, 0x5a, sizeof source);
    source.c = 1;
    source.i = 2;
    memset(&copy, 0, sizeof copy);
    /* A copy of an object carries all of its bytes, the padding between the
     * members included, which is what sizeof says the object is. */
    memcpy(&copy, &source, sizeof source);
    CHECK(memcmp(&copy, &source, sizeof source) == 0);
    CHECK(copy.c == 1 && copy.i == 2);
    return 0;
}
