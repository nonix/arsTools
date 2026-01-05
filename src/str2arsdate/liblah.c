#include "liblah.h"

void str2arsdate(const char* ymd, const int fallback, int* retval) {
    struct tm t = {0};
    struct tm save_t = {0};
    char c[5] = {0};

    *retval = fallback;

    // Cut & check the Year
    strncpy(c,&ymd[0],4);
    t.tm_year = atoi(c)-1900;
    if (t.tm_year < 70 || t.tm_year > 8099) return;
 
    // Cut & check the Month
    bzero(c,sizeof(c));
    strncpy(c,&ymd[4],2);
    t.tm_mon = atoi(c)-1;
    if (t.tm_mon < 0 || t.tm_mon > 11) return;

    // Cut & check the month Day
    bzero(c,sizeof(c));
    strncpy(c,&ymd[6],2);
    t.tm_mday = atoi(c);
    if (t.tm_mday < 1 || t.tm_mday > 31) return;

    // save a copy & convert
    memcpy(&save_t, &t, sizeof(t));
    setenv("TZ","UTC",1);
    tzset();
    time_t epoch = mktime(&t);

    // check for skew
    if (t.tm_year != save_t.tm_year ||
        t.tm_mon  != save_t.tm_mon ||
        t.tm_mday != save_t.tm_mday) return;

    // All OK
    *retval = (epoch/86400+1);
    return;
}
