/* 1106: wcstok-splits-a-wide-string
 *
 * ISO/IEC 9899:1999 7.24.4.9.1: the wcstok function breaks the wide string
 * s1 into a sequence of tokens.
 */

#include <wchar.h>

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
    wchar_t text[16];
    wchar_t *state = NULL;
    wchar_t *tok;
    wmemcpy(text, L"a,b,c", 6);
    tok = wcstok(text, L",", &state);
    CHECK(tok != NULL && wcscmp(tok, L"a") == 0);
    tok = wcstok(NULL, L",", &state);
    CHECK(tok != NULL && wcscmp(tok, L"b") == 0);
    tok = wcstok(NULL, L",", &state);
    CHECK(tok != NULL && wcscmp(tok, L"c") == 0);
    return 0;
}
