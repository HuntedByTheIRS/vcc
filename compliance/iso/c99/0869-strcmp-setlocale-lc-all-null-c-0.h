/* 0869: CHECK(strcmp(setlocale(LC_ALL, NULL), "C") == 0);
 *
 * monolithic.c:12006 (runtime)
 */

#include <stdio.h>
#include <locale.h>
#include <stddef.h>
#include <string.h>
#include <time.h>

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
            time_t epoch_zero = 0;
            time_t now = time(NULL);
            struct tm epoch_fields;
            struct tm local_fields;
            struct tm *epoch_result = gmtime(&epoch_zero);
            struct tm *local_result;
            int have_epoch = 0;
            int have_local = 0;
            char stamp[64];
            clock_t ticks = clock();

            if (epoch_result != NULL) {
                epoch_fields = *epoch_result;      /* copy before anything else */
                have_epoch = 1;
            }
            local_result = localtime(&now);
            if (local_result != NULL) {
                local_fields = *local_result;
                have_local = 1;
            }

            CHECK(now > 0);
            CHECK(have_epoch == 1);
            if (have_epoch) {
                CHECK(epoch_fields.tm_year == 70 && epoch_fields.tm_mon == 0);
                CHECK(epoch_fields.tm_mday == 1);
                CHECK(epoch_fields.tm_wday == 4 && epoch_fields.tm_yday == 0);
                CHECK(epoch_fields.tm_hour == 0 && epoch_fields.tm_min == 0);
                CHECK(epoch_fields.tm_sec == 0 && epoch_fields.tm_isdst == 0);
                {
                    char utc_text[32];
                    char local_text[32];
                    snprintf(utc_text, sizeof utc_text, "%s", asctime(&epoch_fields));
                    CHECK(strcmp(utc_text, "Thu Jan  1 00:00:00 1970\n") == 0);
                    /* ctime is asctime(localtime(t)): the calendar date depends on
                     * the local offset, so only the shape is checked. */
                    snprintf(local_text, sizeof local_text, "%s", ctime(&epoch_zero));
                    CHECK(strlen(local_text) == 25);
                    CHECK(local_text[24] == '\n');
                    CHECK(local_text[3] == ' ' && local_text[7] == ' ');
                    CHECK(local_text[10] == ' ' && local_text[19] == ' ');
                    CHECK(strchr("SMFTW", local_text[0]) != NULL);
                }
                CHECK(strftime(stamp, sizeof stamp, "%Y-%m-%d %H:%M:%S",
                               &epoch_fields) == 19);
                CHECK(strcmp(stamp, "1970-01-01 00:00:00") == 0);
                CHECK(strftime(stamp, sizeof stamp, "%j %U %w", &epoch_fields) == 8);
                CHECK(strcmp(stamp, "001 00 4") == 0);
                /* A buffer too small for the result plus its terminator makes
                 * strftime return 0; the contents are then unspecified. */
                CHECK(strftime(stamp, 4, "%Y-%m-%d", &epoch_fields) == 0);
            }
            if (have_local) {
                CHECK(local_fields.tm_year >= 70);
                CHECK(local_fields.tm_mon >= 0 && local_fields.tm_mon <= 11);
                CHECK(local_fields.tm_mday >= 1 && local_fields.tm_mday <= 31);
                CHECK(local_fields.tm_hour >= 0 && local_fields.tm_hour <= 23);
                CHECK(local_fields.tm_min >= 0 && local_fields.tm_min <= 59);
                CHECK(local_fields.tm_sec >= 0 && local_fields.tm_sec <= 60);
                CHECK(local_fields.tm_isdst >= -1 && local_fields.tm_isdst <= 1);
            }
            /* mktime and localtime are inverses for a wall-clock time built from
             * UTC fields, whatever the local time-zone offset is. */
            if (have_epoch) {
                struct tm rebuilt_fields = epoch_fields;
                time_t rebuilt = mktime(&rebuilt_fields);
                struct tm *again = localtime(&rebuilt);

                CHECK(rebuilt != (time_t)-1);
                CHECK(again != NULL);
                if (again != NULL) {
                    CHECK(again->tm_year == 70 && again->tm_mon == 0);
                    CHECK(again->tm_mday == 1 && again->tm_hour == 0);
                }
                CHECK(difftime(rebuilt, epoch_zero) == (double)(rebuilt - epoch_zero));
                CHECK(difftime(epoch_zero, rebuilt) == -difftime(rebuilt, epoch_zero));
            }
            CHECK(ticks >= (clock_t)0);
            CHECK(CLOCKS_PER_SEC > 0);
            CHECK(time(NULL) >= now);
        }
    {
    const char *current = setlocale(LC_ALL, NULL);
    char saved[64];
    CHECK(current != NULL);
    snprintf(saved, sizeof saved, "%s", current != NULL ? current : "C");
    CHECK(setlocale(LC_ALL, "") != NULL);
    CHECK(setlocale(LC_ALL, "C") != NULL);
    CHECK(strcmp(setlocale(LC_ALL, NULL), "C") == 0);
    }
    return 0;
}
