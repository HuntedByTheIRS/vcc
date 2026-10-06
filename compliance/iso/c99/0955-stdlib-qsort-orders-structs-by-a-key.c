/* 0955: CHECK(v[i].key == i);
 *
 * not in monolithic.c: added after the corpus was split, so it has no line there.
 */

#include <stdio.h>
#include <stdlib.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

struct c99_entry {
    int key;
    int payload;
};

static int compare_entries(const void *left, const void *right)
{
    const struct c99_entry *a = left;
    const struct c99_entry *b = right;
    return (a->key > b->key) - (a->key < b->key);
}

int main(void)
{
    struct c99_entry v[3];
    int i;
    v[0].key = 2;
    v[0].payload = 20;
    v[1].key = 0;
    v[1].payload = 0;
    v[2].key = 1;
    v[2].payload = 10;
    qsort(v, 3, sizeof(struct c99_entry), compare_entries);
    for (i = 0; i < 3; i++) {
        CHECK(v[i].key == i);
        CHECK(v[i].payload == i * 10);
    }
    return 0;
}
