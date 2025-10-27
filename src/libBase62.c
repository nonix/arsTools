// base62.c
#define _POSIX_C_SOURCE 200809L
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <errno.h>
#include <sys/types.h> // ssize_t

static const char BASE62_ALPHABET[] =
  "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";

/* Helper: map ASCII to value (0..61) or 0xFF if invalid */
static void build_revmap(unsigned char rev[256]) {
    for (int i = 0; i < 256; ++i) rev[i] = 0xFF;
    for (int i = 0; i < 62; ++i) rev[(unsigned char)BASE62_ALPHABET[i]] = (unsigned char)i;
}

/* base62_encode:
 * Treat input as big-endian big integer in base 256 and repeatedly divmod by 62.
 * Preserve leading zero bytes -> leading '0' characters in output.
 */
size_t base62_encode(const void *vin, size_t in_len, char *out, size_t out_size) {
    if (vin == NULL && in_len != 0) { errno = EINVAL; return 0; }

    const uint8_t *in = (const uint8_t *)vin;
    if (in_len == 0) {
        /* empty input -> empty string */
        if (out_size > 0) {
            if (out_size >= 1) out[0] = '\0';
        }
        return 0;
    }

    /* count leading zero bytes */
    size_t leading_zeros = 0;
    while (leading_zeros < in_len && in[leading_zeros] == 0) ++leading_zeros;

    /* work on a mutable copy of input bytes (big-endian) */
    uint8_t *bytes = malloc(in_len);
    if (!bytes) { errno = ENOMEM; return 0; }
    memcpy(bytes, in, in_len);
    size_t bytes_len = in_len;

    /* vector to store remainders (digits) in little-endian */
    uint8_t *digits = malloc((in_len * 138 / 100) + 8); // small heuristic cap; will grow if needed
    if (!digits) { free(bytes); errno = ENOMEM; return 0; }
    size_t digits_cap = (in_len * 138 / 100) + 8;
    size_t digits_len = 0;

    /* repeatedly divide bytes by 62 */
    size_t start = 0; /* index of first non-zero in bytes array */
    while (start < bytes_len) {
        /* check if all remaining bytes are zero */
        size_t i;
        int all_zero = 1;
        for (i = start; i < bytes_len; ++i) {
            if (bytes[i] != 0) { all_zero = 0; break; }
        }
        if (all_zero) break;

        unsigned int carry = 0;
        for (i = start; i < bytes_len; ++i) {
            unsigned int cur = (carry << 8) | bytes[i]; /* carry*256 + byte */
            bytes[i] = (uint8_t)(cur / 62);
            carry = cur % 62;
        }
        /* carry is remainder */
        if (digits_len >= digits_cap) {
            size_t newcap = digits_cap * 2;
            uint8_t *tmp = realloc(digits, newcap);
            if (!tmp) { free(bytes); free(digits); errno = ENOMEM; return 0; }
            digits = tmp;
            digits_cap = newcap;
        }
        digits[digits_len++] = (uint8_t)carry;

        /* advance start past leading zeros in the bytes array */
        while (start < bytes_len && bytes[start] == 0) ++start;
    }

    /* resulting length = leading_zeros (as '0' characters) + digits_len (reversed) */
    size_t out_len = leading_zeros + digits_len;
    if (out_size == 0) {
        free(bytes);
        free(digits);
        return out_len;
    }

    if (out_size <= out_len) {
        /* not enough room for chars + NUL (if needed) */
        free(bytes);
        free(digits);
        errno = ENOSPC;
        return 0;
    }

    /* write leading '0' chars for leading zero bytes */
    size_t idx = 0;
    for (size_t i = 0; i < leading_zeros; ++i) out[idx++] = BASE62_ALPHABET[0];

    /* write digits in reverse (most significant first) */
    for (size_t i = 0; i < digits_len; ++i) {
        out[idx++] = BASE62_ALPHABET[digits[digits_len - 1 - i]];
    }

    out[idx] = '\0'; /* NUL-terminate if room (we ensured out_size > out_len) */

    free(bytes);
    free(digits);
    return out_len;
}

/* base62_decode:
 * For each base62 digit, multiply current big-int by 62 and add value.
 * Store big-int as big-endian byte array. Preserve leading '0' characters -> leading zero bytes.
 */
ssize_t base62_decode(const char *in, void *vout, size_t out_size) {
    if (in == NULL) { errno = EINVAL; return -1; }

    unsigned char rev[256];
    build_revmap(rev);

    /* count input length */
    size_t in_len = strlen(in);
    if (in_len == 0) {
        /* empty string -> empty output */
        return 0;
    }

    /* count leading '0' characters */
    size_t leading_zeros = 0;
    while (leading_zeros < in_len && in[leading_zeros] == BASE62_ALPHABET[0]) ++leading_zeros;

    /* big-int bytes (big-endian). Start empty. We'll use dynamic array. */
    uint8_t *bytes = NULL;
    size_t bytes_len = 0;
    size_t bytes_cap = 0;

    /* Helper to prepend a byte (push front) */
    auto prepend_byte = [&](uint8_t b) -> int {
        if (bytes_len + 1 > bytes_cap) {
            size_t newcap = bytes_cap ? bytes_cap * 2 : 8;
            uint8_t *tmp = realloc(bytes, newcap);
            if (!tmp) return 0;
            bytes = tmp;
            bytes_cap = newcap;
        }
        /* move existing data one to the right */
        memmove(bytes + 1, bytes, bytes_len);
        bytes[0] = b;
        bytes_len++;
        return 1;
    };

    /* process each non-leading-zero character */
    for (size_t pos = leading_zeros; pos < in_len; ++pos) {
        unsigned char ch = (unsigned char)in[pos];
        unsigned char val = rev[ch];
        if (val == 0xFF) { /* invalid char */
            free(bytes);
            errno = EINVAL;
            return -1;
        }

        /* big-int multiply by 62, add val */
        unsigned int carry = val;
        if (bytes_len == 0 && carry != 0) {
            /* first non-zero digit: just set bytes to representation of carry */
            /* carry might be >255 (no, carry < 62) but multiplication may grow later */
            if (!prepend_byte((uint8_t)carry)) { free(bytes); errno = ENOMEM; return -1; }
            continue;
        }

        /* multiply from least-significant (right) to most-significant (left)
         * but our storage is big-endian, so iterate from bytes_len-1 down to 0 */
        for (ssize_t i = (ssize_t)bytes_len - 1; i >= 0; --i) {
            unsigned int prod = (unsigned int)bytes[i] * 62 + carry;
            bytes[i] = (uint8_t)(prod & 0xFF);
            carry = prod >> 8;
        }
        /* propagate carry */
        while (carry) {
            if (!prepend_byte((uint8_t)(carry & 0xFF))) { free(bytes); errno = ENOMEM; return -1; }
            carry >>= 8;
        }
    }

    /* Now bytes[] holds the binary value for the non-leading-zero portion.
     * Final payload = leading_zeros zero bytes followed by bytes[].
     */
    size_t total_len = leading_zeros + bytes_len;
    if (vout == NULL && out_size != 0) { free(bytes); errno = EINVAL; return -1; }

    if (out_size == 0) {
        free(bytes);
        return (ssize_t)total_len; /* caller asked for size */
    }

    if (out_size < total_len) {
        free(bytes);
        errno = ENOSPC;
        return -1;
    }

    uint8_t *out = (uint8_t *)vout;
    /* write leading zero bytes */
    memset(out, 0, leading_zeros);
    /* copy big-int bytes after them */
    if (bytes_len > 0) memcpy(out + leading_zeros, bytes, bytes_len);

    free(bytes);
    return (ssize_t)total_len;
}
