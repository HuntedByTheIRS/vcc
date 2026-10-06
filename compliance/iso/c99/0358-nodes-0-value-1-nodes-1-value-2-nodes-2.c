/* 0358: CHECK(nodes[0].value == 1 && nodes[1].value == 2 && nodes[2].value == 3);
 *
 * monolithic.c:10712 (arrays)
 */

#include <stdio.h>

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

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    {
    struct c99_nested n = {.point = {.y = 2, .x = 1}, .chain[1] = {4, NULL}};
    struct c99_node nodes[3] = {[0] = {1, NULL}, [2] = {3, NULL}, [1] = {2, NULL}};
    CHECK(n.point.x == 1 && n.point.y == 2);
    CHECK(n.chain[1].value == 4 && n.chain[0].value == 0);
    CHECK(nodes[0].value == 1 && nodes[1].value == 2 && nodes[2].value == 3);
    }
    return 0;
}
