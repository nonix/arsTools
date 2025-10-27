ssize_t base62_decode(const char *in, void *vout, size_t out_size) {
    if (in == NULL) { errno = EINVAL; return -1; }

    unsigned char rev[256];
    build_revmap(rev);

    size_t in_len = strlen(in);
    if (in_len == 0) return 0;

    /* count leading '0' characters */
    size_t leading_zeros = 0;
    while (leading_zeros < in_len && in[leading_zeros] == BASE62_ALPHABET[0]) ++leading_zeros;

    /* big integer buffer (big-endian) */
    uint8_t *bytes = NULL;
    size_t bytes_len = 0;
    size_t bytes_cap = 0;

    /* ensure capacity, prepend a byte at the beginning */
    #define ENSURE_CAPACITY(n) \
        do { \
            if ((n) > bytes_cap) { \
                size_t newcap = bytes_cap ? bytes_cap * 2 : 8; \
                while (newcap < (n)) newcap *= 2; \
                uint8_t *tmp = realloc(bytes, newcap); \
                if (!tmp) { free(bytes); errno = ENOMEM; return -1; } \
                bytes = tmp; \
                bytes_cap = newcap; \
            } \
        } while (0)

    /* process each non-leading-zero character */
    for (size_t pos = leading_zeros; pos < in_len; ++pos) {
        unsigned char ch = (unsigned char)in[pos];
        unsigned char val = rev[ch];
        if (val == 0xFF) { free(bytes); errno = EINVAL; return -1; }

        /* multiply big-int by 62 and add val */
        unsigned int carry = val;

        if (bytes_len == 0) {
            /* first digit */
            ENSURE_CAPACITY(1);
            bytes[0] = carry;
            bytes_len = 1;
            continue;
        }

        /* multiply existing number by 62 */
        for (ssize_t i = (ssize_t)bytes_len - 1; i >= 0; --i) {
            unsigned int prod = (unsigned int)bytes[i] * 62 + carry;
            bytes[i] = (uint8_t)(prod & 0xFF);
            carry = prod >> 8;
        }

        /* handle remaining carry */
        while (carry) {
            ENSURE_CAPACITY(bytes_len + 1);
            memmove(bytes + 1, bytes, bytes_len);
            bytes[0] = (uint8_t)(carry & 0xFF);
            bytes_len++;
            carry >>= 8;
        }
    }

    #undef ENSURE_CAPACITY

    size_t total_len = leading_zeros + bytes_len;

    if (out_size == 0) {
        free(bytes);
        return (ssize_t)total_len;
    }

    if (out_size < total_len) {
        free(bytes);
        errno = ENOSPC;
        return -1;
    }

    uint8_t *out = (uint8_t *)vout;
    memset(out, 0, leading_zeros);
    if (bytes_len > 0)
        memcpy(out + leading_zeros, bytes, bytes_len);

    free(bytes);
    return (ssize_t)total_len;
}
