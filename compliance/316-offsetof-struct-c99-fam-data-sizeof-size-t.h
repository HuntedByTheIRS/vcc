/* 316: CHECK(offsetof(struct c99_fam, data) == sizeof(size_t));
 *
 * monolithic.c:10569 (aggregates)
 */

#include <stdio.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

struct c99_node {                    /* self-referential structure */
    int value;
    struct c99_node *next;
};

struct c99_nested {                  /* struct inside struct inside struct */
    struct {
        int x;
        int y;
    } point;
    union {
        int as_int;
        char as_bytes[sizeof(int)];
    } pun;
    struct c99_node chain[2];
};

struct c99_fam {
    size_t length;
    char data[];
};

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    struct c99_nested nested = {
            {1, 2},
            {0},
            {{3, NULL}, {4, NULL}}
        };
    struct c99_nested copy;
    struct c99_fam *fam;
    struct c99_node a = {1, NULL};
    struct c99_node b = {2, &a};
    CHECK(nested.point.x == 1 && nested.point.y == 2);
    CHECK(nested.chain[0].value == 3 && nested.chain[1].value == 4);
    CHECK(nested.chain[0].next == NULL && nested.chain[1].next == NULL);
    copy = nested;
    copy.point.x = 99;
    copy.chain[1].value = 44;
    CHECK(nested.point.x == 1 && copy.point.x == 99);
    CHECK(nested.chain[1].value == 4 && copy.chain[1].value == 44);
    a.next = &b;
    CHECK(b.next->next->value == 2);
    fam = malloc(sizeof *fam + 16);
    CHECK(fam != NULL);
    if (fam != NULL) {
            fam->length = 16;
            memcpy(fam->data, "0123456789abcdef", 16);
            CHECK(fam->length == 16);
            CHECK(fam->data[0] == '0' && fam->data[15] == 'f');
            CHECK(sizeof *fam == sizeof(size_t));    /* FAM is not counted */
            free(fam);
        }
    CHECK(offsetof(struct c99_nested, point.y) == sizeof(int));
    CHECK(offsetof(struct c99_nested, chain) > offsetof(struct c99_nested, point));
    CHECK(offsetof(struct c99_fam, data) == sizeof(size_t));
    return 0;
}
