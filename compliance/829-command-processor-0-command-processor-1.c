/* 829: CHECK(command_processor == 0 || command_processor == 1);
 *
 * monolithic.c:11828 (utilities)
 */

#include <stdio.h>
#include <stddef.h>
#include <stdlib.h>

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
    int command_processor = system(NULL);
    CHECK(command_processor == 0 || command_processor == 1);
    }
    return 0;
}
