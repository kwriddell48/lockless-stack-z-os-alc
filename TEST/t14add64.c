/* T14ADD64 - STATADD64 / STATADD64S / STATMAX64 + SCB alignment. */
#define _OPEN_THREADS 1
#include "mpmcs.h"

#ifdef __MVS__
#pragma runopts(POSIX(ON))
#endif

#include <pthread.h>

#define NTHR 4
#define NADD 10000u

/* CDS / LAAL fields relative to a 0D-aligned SCB. */
#define SCB_OFF_TOP    32u
#define SCB_OFF_FREE   40u
#define SCB_OFF_WORK   48u
#define SCB_OFF_P31CUR 136u

#ifdef __MVS__
#pragma linkage(CS64ADD, OS)
#pragma linkage(CS64ADS, OS)
#pragma linkage(CS64MAX, OS)
#endif
extern int32_t CS64ADD(void *plist);
extern int32_t CS64ADS(void *plist);
extern int32_t CS64MAX(void *plist);

typedef struct {
    void     *dwaddr;
    uint32_t  addend;
} S64AddPlist;

typedef struct {
    void     *dwaddr;
    uint32_t  cand_hi;
    uint32_t  cand_lo;
} S64MaxPlist;

typedef struct {
    uint64_t *dw;
    uint32_t  addend;
    uint32_t  count;
} AddArg;

static int32_t s64add(uint64_t *dw, uint32_t addend)
{
    S64AddPlist pl;
    memset(&pl, 0, sizeof(pl));
    pl.dwaddr = dw;
    pl.addend = addend;
    return CS64ADD(&pl);
}

static int32_t s64adds(uint64_t *dw, uint32_t addend)
{
    S64AddPlist pl;
    memset(&pl, 0, sizeof(pl));
    pl.dwaddr = dw;
    pl.addend = addend;
    return CS64ADS(&pl);
}

static int32_t s64max(uint64_t *dw, uint32_t hi, uint32_t lo)
{
    S64MaxPlist pl;
    memset(&pl, 0, sizeof(pl));
    pl.dwaddr  = dw;
    pl.cand_hi = hi;
    pl.cand_lo = lo;
    return CS64MAX(&pl);
}

static void *adder(void *arg)
{
    AddArg *a = (AddArg *)arg;
    uint32_t i;
    for (i = 0; i < a->count; i++) {
        if (s64add(a->dw, a->addend) != 0) {
            a->count = 0;
            return 0;
        }
    }
    return 0;
}

int main(void)
{
    uint64_t dw;
    void *scb;
    pthread_t th[NTHR];
    AddArg args[NTHR];
    int i;

    printf("T14ADD64 start\n");
    fflush(stdout);

    scb = mpmcs_alloc_scb();
    TEST_EXPECT(scb != NULL, "SCB alloc");
    TEST_EXPECT(((unsigned long)scb & 7ul) == 0, "SCB not 8-aligned");
    TEST_EXPECT((SCB_OFF_TOP & 7u) == 0, "TOP offset");
    TEST_EXPECT((SCB_OFF_FREE & 7u) == 0, "FREE offset");
    TEST_EXPECT((SCB_OFF_WORK & 7u) == 0, "WORK offset");
    TEST_EXPECT((SCB_OFF_P31CUR & 7u) == 0, "P31CUR offset");
    TEST_RC(mpmcs_sinit(scb, MPMCS_OPT_PAYLOAD31, 0, 0, 0),
            MPMCS_RC_OK, "SINIT");
    TEST_EXPECT(mpmcs_check_eye(scb), "eyecatcher");
    mpmcs_scbstop(scb);
    mpmcs_free(scb);

    /* STATADD64 unsigned boundaries */
    dw = 0;
    TEST_RC(s64add(&dw, 0), 0, "add 0");
    TEST_EXPECT(dw == 0, "0+0");
    TEST_RC(s64add(&dw, 1), 0, "add 1");
    TEST_EXPECT(dw == 1, "0+1");
    dw = 0;
    TEST_RC(s64add(&dw, 0xFFFFFFFFu), 0, "add maxu");
    TEST_EXPECT(dw == 0xFFFFFFFFull, "0+maxu");
    TEST_RC(s64add(&dw, 1), 0, "carry");
    TEST_EXPECT(dw == 0x100000000ull, "maxu+1");
    dw = 0xFFFFFFFFull;
    TEST_RC(s64add(&dw, 0xFFFFFFFFu), 0, "maxu+maxu");
    TEST_EXPECT(dw == 0x1FFFFFFFEull, "maxu+maxu val");
    dw = 0xFFFFFFFF00000000ull;
    TEST_RC(s64add(&dw, 1), 0, "hi only");
    TEST_EXPECT(dw == 0xFFFFFFFF00000001ull, "hi+1");
    dw = 0xFFFFFFFFFFFFFFFFull;
    TEST_RC(s64add(&dw, 1), 0, "u64 wrap");
    TEST_EXPECT(dw == 0, "wrap to 0");
    dw = 0xFFFFFFFEull;
    TEST_RC(s64add(&dw, 2), 0, "fe+2");
    TEST_EXPECT(dw == 0x100000000ull, "fe+2 val");

    /* STATADD64S signed boundaries (addend is two's complement) */
    dw = 4;
    TEST_RC(s64adds(&dw, (uint32_t)-2), 0, "4+(-2)");
    TEST_EXPECT(dw == 2, "4-2");
    dw = 1;
    TEST_RC(s64adds(&dw, (uint32_t)-1), 0, "1+(-1)");
    TEST_EXPECT(dw == 0, "1-1");
    dw = 0;
    TEST_RC(s64adds(&dw, (uint32_t)-1), 0, "0+(-1)");
    TEST_EXPECT(dw == 0xFFFFFFFFFFFFFFFFull, "underflow");
    dw = 0x100000000ull;
    TEST_RC(s64adds(&dw, (uint32_t)-1), 0, "2^32-1");
    TEST_EXPECT(dw == 0xFFFFFFFFull, "2^32-1 val");
    dw = 0xFFFFFFFFull;
    TEST_RC(s64adds(&dw, (uint32_t)-1), 0, "maxu-1");
    TEST_EXPECT(dw == 0xFFFFFFFEull, "carry+neg");
    dw = 5;
    TEST_RC(s64adds(&dw, 0), 0, "5+0");
    TEST_EXPECT(dw == 5, "5+0 val");

    /* STATMAX64 must be unsigned: 0x80.. beats 0x7F.. */
    dw = 0x7FFFFFFFFFFFFFFFull;
    TEST_RC(s64max(&dw, 0x80000000u, 0), 0, "umax");
    TEST_EXPECT(dw == 0x8000000000000000ull, "unsigned max");
    TEST_RC(s64max(&dw, 0x7FFFFFFFu, 0xFFFFFFFFu), 0, "smaller");
    TEST_EXPECT(dw == 0x8000000000000000ull, "max held");

    dw = 0;
    for (i = 0; i < NTHR; i++) {
        args[i].dw = &dw;
        args[i].addend = 1;
        args[i].count = NADD;
        if (pthread_create(&th[i], 0, adder, &args[i]) != 0)
            TEST_FAIL("pthread_create");
    }
    for (i = 0; i < NTHR; i++)
        pthread_join(th[i], 0);
    for (i = 0; i < NTHR; i++)
        TEST_EXPECT(args[i].count == NADD, "adder rc");
    TEST_EXPECT(dw == (uint64_t)NTHR * NADD, "MP sum");

    printf("T14ADD64 PASS dw=%llu\n", (unsigned long long)dw);
    return 0;
}
