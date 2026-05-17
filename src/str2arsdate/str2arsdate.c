#include <string.h>

// Exact signature requested
void str2arsdate(const char* ymd, const int* fallback, int* retval) 
{
    int is_valid = 1;
    int y, m, d;
    int epoch;
    
    // Days completed before each month (Index 0=Jan, 11=Dec)
    const int days_to_month[12] = {0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334};

    /* ---------------------------------------------------------
       FAST VALIDATION & INTEGER CONVERSION
       --------------------------------------------------------- */
    // 1. Length & Numeric check (ASCII '0' is 48, '9' is 57)
    if (ymd == NULL || ymd[8] != '\0') {
        is_valid = 0;
    } else {
        int d0 = ymd[0] - 48; if (d0 > 9) { is_valid = 0; }
        int d1 = ymd[1] - 48; if (d1 > 9) { is_valid = 0; }
        int d2 = ymd[2] - 48; if (d2 > 9) { is_valid = 0; }
        int d3 = ymd[3] - 48; if (d3 > 9) { is_valid = 0; }
        int d4 = ymd[4] - 48; if (d4 > 9) { is_valid = 0; }
        int d5 = ymd[5] - 48; if (d5 > 9) { is_valid = 0; }
        int d6 = ymd[6] - 48; if (d6 > 9) { is_valid = 0; }
        int d7 = ymd[7] - 48; if (d7 > 9) { is_valid = 0; }

        if (is_valid) {
            // 2. Construct Year, Month, Day integers
            y = (d0 * 10 + d1) * 10 + d2;
            y = y * 10 + d3;
            m = d4 * 10 + d5;
            d = d6 * 10 + d7;

            // 3. Calendar validation
            if (m < 1 || m > 12 || d < 1) {
                is_valid = 0;
            } else {
                int max_d = 31;
                if (m == 4 || m == 6 || m == 9 || m == 11) {
                    max_d = 30;
                } else if (m == 2) {
                    // Fast bitwise leap year check
                    max_d = ((y & 3) == 0 && (y % 100 != 0 || y % 400 == 0)) ? 29 : 28;
                }
                if (d > max_d) {
                    is_valid = 0;
                }
            }
        }
    }

    /* ---------------------------------------------------------
       EPOCH CALCULATION
       --------------------------------------------------------- */
    if (is_valid) {
        // Standard formula for days since year 0
        epoch = y * 365 + (y - 1) / 4 - (y - 1) / 100 + (y - 1) / 400;
        
        // Add days from completed months
        epoch += days_to_month[m - 1];
        
        // Add leap day if past February in a leap year
        if (m > 2 && ((y & 3) == 0) && (y % 100 != 0 || y % 400 == 0)) {
            epoch += 1;
        }
        
        // Add current day
        epoch += d;
        
        // Anchor 1970-01-01 to 1 (Subtracting 719528 does exactly this)
        epoch -= 719527;

        *retval = epoch;
    } else {
        // Invalid date: Just return the pre-calculated fallback integer
        *retval = *fallback;
    }
}

