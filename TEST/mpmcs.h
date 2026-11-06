/* C test API for the MPMC HLASM stack.
 *
 * Assembler entries use OS linkage with R1 -> value plist (DSECT),
 * not LE C's list-of-pointers. Call through mpmcs_* wrappers.
 *
 * Compile AMODE 31, NOXPLINK, ILP32. Link with the stack objects
 * plus TEST/cglue.asm (and TEST/testcb.asm for t11cb).
 */
#ifndef MPMCS_TEST_H
#define MPMCS_TEST_H

#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MPMCS_OPT_PAYLOAD31  0x00000000u
#define MPMCS_OPT_PAYLOAD64  0x00000001u
#define MPMCS_OPT_TRACE      0x00000002u
#define MPMCS_NODE_PREFILL(n) ((uint32_t)(n) << 16)

#define MPMCS_TRC_SLOTS      256u
#define MPMCS_TRC_SLOT       32u
#define MPMCS_TRC_HDR        16u
#define MPMCS_TRC_API        0x01u
#define MPMCS_TRC_CDS        0x02u
#define MPMCS_TRC_NTF        0x04u
#define MPMCS_TRC_ALC        0x08u
#define MPMCS_TRC_ALL        0x0Fu
#define MPMCS_TRE_SINIT      1
#define MPMCS_TRE_SINITX     2
#define MPMCS_TRE_SPUSH      3
#define MPMCS_TRE_SPUSHX     4
#define MPMCS_TRE_SPOP       5
#define MPMCS_TRE_SPOPX      6
#define MPMCS_TRE_CDSOK      9
#define MPMCS_TRE_CDSRET     10

#define MPMCS_RC_OK          0
#define MPMCS_RC_EMPTY       4
#define MPMCS_RC_TRUNC       8
#define MPMCS_RC_ALLOC_FAIL  8
/* One MVCL; SPUSH rejects a longer srcLen with RC=8. */
#define MPMCS_MAX_COPY       0x00FFFFFFu

/* Must be >= SCB_SIZE in src/dsects.inc (currently 280). Extra bytes
 * after the DSECT are unused; keep this in sync if the SCB grows. */
#define MPMCS_SCB_SIZE   280u
#define MPMCS_SCB_ALLOC  512u

#define MPMCS_STATS_VERSION 1

#define MPMCS_EYE "MPMCSTK "

typedef struct {
    uint32_t version;
    uint32_t size;
    uint32_t push_ok;
    uint32_t pop_ok;
    uint32_t pop_empty;
    uint32_t push_alloc_fail;
    uint32_t push_retry;
    uint32_t pop_retry;
    uint32_t freelist_pop_retry;
    uint32_t freelist_push_retry;
    uint32_t depth_cur;
    uint32_t depth_max;
    uint64_t payload31_cur;
    uint64_t payload31_max;
    uint64_t payload64_cur;
    uint64_t payload64_max;
    uint32_t post_internal;
    uint32_t post_userecb;
    uint32_t cb_calls;
    uint32_t cb_pending_max;
} MpmcsStats;

typedef struct {
    void     *scbaddr;
    uint32_t  options;
    void     *cb_ep;
    void     *cb_ctx;
    void     *user_ecb;
} MpmcsSinitPlist;

typedef struct {
    void     *scbaddr;
    const void *srcaddr;
    uint32_t  srclen;
} MpmcsSpushPlist;

typedef struct {
    void     *scbaddr;
    void     *dstaddr;
    uint32_t  dstmax;
    uint32_t *outlenaddr;
} MpmcsSpopPlist;

typedef struct {
    void     *scbaddr;
    void     *outaddr;
    uint32_t  outlen;
} MpmcsSstatsPlist;

typedef struct {
    char     *outaddr;
    uint32_t  outmax;
    uint32_t *outactlenaddr;
} MpmcsGetverPlist;

typedef struct {
    void     *scbaddr;
} MpmcsScbstopPlist;

typedef struct {
    void     *scbaddr;
    void     *outaddr;
    uint32_t  outlen;
} MpmcsStracePlist;

typedef struct {
    void     *scbaddr;
    uint32_t  mask;
} MpmcsStrsetPlist;

typedef struct {
    uint32_t next;
    uint32_t n;
    uint32_t mask;
    uint32_t slot;
} MpmcsTrcHdr;

void     *mpmcs_alloc(size_t n);
void      mpmcs_free(void *p);
void     *mpmcs_alloc_scb(void);

int32_t   mpmcs_sinit(void *scb, uint32_t options,
                      void *cb_ep, void *cb_ctx, void *user_ecb);
int32_t   mpmcs_spush(void *scb, const void *src, uint32_t src_len);
int32_t   mpmcs_spop(void *scb, void *dst, uint32_t dst_max,
                     uint32_t *out_len);
int32_t   mpmcs_sstats(void *scb, MpmcsStats *out);
int32_t   mpmcs_scbstop(void *scb);
int32_t   mpmcs_getversion(char *out, uint32_t out_max, uint32_t *act);
int32_t   mpmcs_strace(void *scb, void *out, uint32_t out_len);
int32_t   mpmcs_straceset(void *scb, uint32_t mask);

int       mpmcs_check_eye(const void *scb);
void      mpmcs_spin(unsigned loops);

/* Keep these macros inside cols 1-72 (PDS C: 73-80 are sequence). */
int mpmcs_fail(const char *file, int line, const char *msg);
int mpmcs_chkrc(int32_t rc, int32_t want, const char *file, int line,
                const char *what);

#define TEST_FAIL(m) return mpmcs_fail(__FILE__, __LINE__, (m))
#define TEST_EXPECT(c, m) if (!(c)) TEST_FAIL(m)
#define TEST_RC(r, w, t) \
 if (mpmcs_chkrc((r), (w), __FILE__, __LINE__, (t))) return 8

#endif
