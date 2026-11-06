/* Plist builders + trampoline calls into the HLASM stack. */
#include "mpmcs.h"

#ifdef __MVS__
#pragma linkage(CSINIT, OS)
#pragma linkage(CSPUSH, OS)
#pragma linkage(CSPOP, OS)
#pragma linkage(CSSTATS, OS)
#pragma linkage(CSCBSTP, OS)
#pragma linkage(CGETVER, OS)
#pragma linkage(CSTRACE, OS)
#pragma linkage(CSTRSET, OS)
extern void *__malloc31(size_t);
#endif
extern int32_t CSINIT(void *plist);
extern int32_t CSPUSH(void *plist);
extern int32_t CSPOP(void *plist);
extern int32_t CSSTATS(void *plist);
extern int32_t CSCBSTP(void *plist);
extern int32_t CGETVER(void *plist);
extern int32_t CSTRACE(void *plist);
extern int32_t CSTRSET(void *plist);

void *mpmcs_alloc(size_t n)
{
    void *p;
#if defined(__MVS__)
    p = __malloc31(n);
#else
    p = malloc(n);
#endif
    if (p != NULL)
        memset(p, 0, n);
    return p;
}

void mpmcs_free(void *p)
{
    free(p);
}

void *mpmcs_alloc_scb(void)
{
    return mpmcs_alloc(MPMCS_SCB_ALLOC);
}

int32_t mpmcs_sinit(void *scb, uint32_t options,
                    void *cb_ep, void *cb_ctx, void *user_ecb)
{
    MpmcsSinitPlist pl;
    memset(&pl, 0, sizeof(pl));
    pl.scbaddr  = scb;
    pl.options  = options;
    pl.cb_ep    = cb_ep;
    pl.cb_ctx   = cb_ctx;
    pl.user_ecb = user_ecb;
    return CSINIT(&pl);
}

int32_t mpmcs_spush(void *scb, const void *src, uint32_t src_len)
{
    MpmcsSpushPlist pl;
    memset(&pl, 0, sizeof(pl));
    pl.scbaddr = scb;
    pl.srcaddr = src;
    pl.srclen  = src_len;
    return CSPUSH(&pl);
}

int32_t mpmcs_spop(void *scb, void *dst, uint32_t dst_max,
                   uint32_t *out_len)
{
    MpmcsSpopPlist pl;
    memset(&pl, 0, sizeof(pl));
    pl.scbaddr    = scb;
    pl.dstaddr    = dst;
    pl.dstmax     = dst_max;
    pl.outlenaddr = out_len;
    return CSPOP(&pl);
}

int32_t mpmcs_sstats(void *scb, MpmcsStats *out)
{
    MpmcsSstatsPlist pl;
    memset(&pl, 0, sizeof(pl));
    memset(out, 0, sizeof(*out));
    pl.scbaddr = scb;
    pl.outaddr = out;
    pl.outlen  = (uint32_t)sizeof(*out);
    return CSSTATS(&pl);
}

int32_t mpmcs_scbstop(void *scb)
{
    MpmcsScbstopPlist pl;
    memset(&pl, 0, sizeof(pl));
    pl.scbaddr = scb;
    return CSCBSTP(&pl);
}

int32_t mpmcs_getversion(char *out, uint32_t out_max, uint32_t *act)
{
    MpmcsGetverPlist pl;
    memset(&pl, 0, sizeof(pl));
    pl.outaddr       = out;
    pl.outmax        = out_max;
    pl.outactlenaddr = act;
    return CGETVER(&pl);
}

int32_t mpmcs_strace(void *scb, void *out, uint32_t out_len)
{
    MpmcsStracePlist pl;
    memset(&pl, 0, sizeof(pl));
    pl.scbaddr = scb;
    pl.outaddr = out;
    pl.outlen  = out_len;
    return CSTRACE(&pl);
}

int32_t mpmcs_straceset(void *scb, uint32_t mask)
{
    MpmcsStrsetPlist pl;
    memset(&pl, 0, sizeof(pl));
    pl.scbaddr = scb;
    pl.mask    = mask;
    return CSTRSET(&pl);
}

int mpmcs_check_eye(const void *scb)
{
    return memcmp(scb, MPMCS_EYE, 8) == 0;
}

void mpmcs_spin(unsigned loops)
{
    volatile unsigned i;
    for (i = 0; i < loops; i++)
        ;
}

int mpmcs_fail(const char *file, int line, const char *msg)
{
    fprintf(stderr, "FAIL %s:%d: %s\n", file, line, msg);
    return 8;
}

int mpmcs_chkrc(int32_t rc, int32_t want, const char *file, int line,
                const char *what)
{
    if (rc == want)
        return 0;
    fprintf(stderr, "FAIL %s:%d: %s rc=%d want=%d\n",
            file, line, what, (int)rc, (int)want);
    return 8;
}
