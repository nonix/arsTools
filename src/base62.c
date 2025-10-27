#define _POSIX_C_SOURCE 200809L
#include <sys/types.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <stdio.h>
#include <unistd.h>

/* ===== Base62 core ===== */

static const char BASE62_ALPHABET[] =
    "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";

static void build_revmap(unsigned char rev[256]) {
    size_t i;
    for (i = 0; i < 256; ++i)
        rev[i] = 0xFF;
    for (i = 0; i < 62; ++i)
        rev[(unsigned char)BASE62_ALPHABET[i]] = (unsigned char)i;
}

size_t base62_encode(const void *vin, size_t in_len, char *out, size_t out_size) {
    const uint8_t *in = (const uint8_t *)vin;
    if (!in && in_len != 0) { errno = EINVAL; return 0; }

    size_t leading_zeros = 0;
    while (leading_zeros < in_len && in[leading_zeros] == 0) ++leading_zeros;

    uint8_t *bytes = malloc(in_len);
    if (!bytes) { errno = ENOMEM; return 0; }
    memcpy(bytes, in, in_len);
    size_t bytes_len = in_len;

    size_t digits_cap = (in_len * 138 / 100) + 8;
    uint8_t *digits = malloc(digits_cap);
    if (!digits) { free(bytes); errno = ENOMEM; return 0; }
    size_t digits_len = 0;

    size_t start = 0;
    while (start < bytes_len) {
        unsigned int carry = 0;
        for (size_t i = start; i < bytes_len; ++i) {
            unsigned int cur = (carry << 8) | bytes[i];
            bytes[i] = (uint8_t)(cur / 62);
            carry = cur % 62;
        }
        digits[digits_len++] = (uint8_t)carry;
        while (start < bytes_len && bytes[start] == 0) ++start;
    }

    size_t out_len = leading_zeros + digits_len;
    if (out_size == 0) { free(bytes); free(digits); return out_len; }

    if (out_size <= out_len) { free(bytes); free(digits); errno = ENOSPC; return 0; }

    size_t idx = 0;
    for (size_t i = 0; i < leading_zeros; ++i)
        out[idx++] = BASE62_ALPHABET[0];
    for (size_t i = 0; i < digits_len; ++i)
        out[idx++] = BASE62_ALPHABET[digits[digits_len - 1 - i]];

    out[idx] = '\0';
    free(bytes);
    free(digits);
    return out_len;
}

ssize_t base62_decode(const char *in, void *vout, size_t out_size) {
    if (in == NULL) { errno = EINVAL; return -1; }

    unsigned char rev[256];
    build_revmap(rev);

    size_t in_len = strlen(in);
    size_t leading_zeros = 0;
    while (leading_zeros < in_len && in[leading_zeros] == BASE62_ALPHABET[0])
        ++leading_zeros;

    uint8_t *bytes = NULL;
    size_t bytes_len = 0, bytes_cap = 0;

#define ENSURE_CAP(n) \
    do { \
        if ((n) > bytes_cap) { \
            size_t nc = bytes_cap ? bytes_cap * 2 : 8; \
            while (nc < (n)) nc *= 2; \
            uint8_t *tmp = realloc(bytes, nc); \
            if (!tmp) { free(bytes); errno = ENOMEM; return -1; } \
            bytes = tmp; bytes_cap = nc; \
        } \
    } while (0)

    for (size_t pos = leading_zeros; pos < in_len; ++pos) {
        unsigned char ch = (unsigned char)in[pos];
        unsigned char val = rev[ch];
        if (val == 0xFF) { free(bytes); errno = EINVAL; return -1; }

        unsigned int carry = val;
        if (bytes_len == 0) {
            ENSURE_CAP(1);
            bytes[0] = carry;
            bytes_len = 1;
            continue;
        }

        for (ssize_t i = (ssize_t)bytes_len - 1; i >= 0; --i) {
            unsigned int prod = bytes[i] * 62 + carry;
            bytes[i] = (uint8_t)(prod & 0xFF);
            carry = prod >> 8;
        }

        while (carry) {
            ENSURE_CAP(bytes_len + 1);
            memmove(bytes + 1, bytes, bytes_len);
            bytes[0] = (uint8_t)(carry & 0xFF);
            bytes_len++;
            carry >>= 8;
        }
    }
#undef ENSURE_CAP

    size_t total_len = leading_zeros + bytes_len;
    if (out_size == 0) { free(bytes); return (ssize_t)total_len; }
    if (out_size < total_len) { free(bytes); errno = ENOSPC; return -1; }

    uint8_t *out = (uint8_t *)vout;
    memset(out, 0, leading_zeros);
    if (bytes_len) memcpy(out + leading_zeros, bytes, bytes_len);

    free(bytes);
    return (ssize_t)total_len;
}

/* ===== CLI utility (like base64) ===== */

static void usage(const char *prog) {
    fprintf(stderr,
        "Usage: %s [-d] [-w cols] [input [output]]\n"
        "  -d        Decode instead of encode\n"
        "  -w cols   Wrap encoded lines (0 disables)\n",
        prog);
}

int main(int argc, char **argv) {
    int decode = 0;
    size_t wrap = 0;
    int opt;

    while ((opt = getopt(argc, argv, "dw:")) != -1) {
        switch (opt) {
            case 'd': decode = 1; break;
            case 'w': wrap = (size_t)atoi(optarg); break;
            default: usage(argv[0]); return 1;
        }
    }

    const char *infile = NULL, *outfile = NULL;
    if (optind < argc) infile = argv[optind++];
    if (optind < argc) outfile = argv[optind++];

    FILE *in = infile ? fopen(infile, decode ? "rb" : "rb") : stdin;
    FILE *out = outfile ? fopen(outfile, decode ? "wb" : "wb") : stdout;
    if (!in || !out) {
        perror("file");
        if (in && in != stdin) fclose(in);
        if (out && out != stdout) fclose(out);
        return 1;
    }

    if (!decode) {
        /* ENCODE */
        unsigned char buf[1024];
        char outbuf[4096];
        size_t n, written = 0;
        while ((n = fread(buf, 1, sizeof(buf), in)) > 0) {
            size_t need = base62_encode(buf, n, NULL, 0);
            if (need >= sizeof(outbuf)) {
                fprintf(stderr, "internal buffer too small\n");
                return 1;
            }
            base62_encode(buf, n, outbuf, sizeof(outbuf));
            for (size_t i = 0; i < need; ++i) {
                fputc(outbuf[i], out);
                if (wrap && ++written >= wrap) {
                    fputc('\n', out);
                    written = 0;
                }
            }
        }
        if (wrap && written > 0)
            fputc('\n', out);
    } else {
        /* DECODE */
        char inbuf[4096];
        unsigned char outbuf[4096];
        size_t len = 0;
        int c;
        while ((c = fgetc(in)) != EOF) {
            if (c == '\n' || c == '\r') continue;
            inbuf[len++] = (char)c;
            if (len >= sizeof(inbuf) - 1) {
                inbuf[len] = '\0';
                ssize_t need = base62_decode(inbuf, outbuf, sizeof(outbuf));
                if (need < 0) { perror("decode"); return 1; }
                fwrite(outbuf, 1, (size_t)need, out);
                len = 0;
            }
        }
        if (len > 0) {
            inbuf[len] = '\0';
            ssize_t need = base62_decode(inbuf, outbuf, sizeof(outbuf));
            if (need < 0) { perror("decode"); return 1; }
            fwrite(outbuf, 1, (size_t)need, out);
        }
    }

    if (in && in != stdin) fclose(in);
    if (out && out != stdout) fclose(out);
    return 0;
}
