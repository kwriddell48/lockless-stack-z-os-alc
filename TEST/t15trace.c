/* T15TRACE - flight recorder STRACE / STRACESET. */
#include "mpmcs.h"

#define DUMP_N (16u + 256u * 32u)

static int count_ev(const unsigned char *ring,
                    uint32_t next, uint32_t n,
                    unsigned cls, unsigned ev)
{
    uint32_t i, lim, c;
    const unsigned char *s;
    lim = next;
    if (lim > n)
        lim = n;
    c = 0;
    for (i = 0; i < lim; i++) {
        s = ring + (i * 32u);
        if (s[8] == (unsigned char)cls &&
            s[9] == (unsigned char)ev)
            c++;
    }
    return (int)c;
}

int main(void)
{
    void *scb;
    unsigned char *dump;
    uint32_t next0, next1, n, mask, slot;
    unsigned char *ring;
    char out[8];
    uint32_t len = 0;
    int npush;

    printf("T15TRACE start\n");
    fflush(stdout);

    scb = mpmcs_alloc_scb();
    TEST_EXPECT(scb != NULL, "SCB alloc failed");
    dump = (unsigned char *)mpmcs_alloc(DUMP_N);
    TEST_EXPECT(dump != NULL, "dump alloc failed");

    TEST_RC(mpmcs_sinit(scb,
            MPMCS_NODE_PREFILL(4) | MPMCS_OPT_PAYLOAD31,
            0, 0, 0),
            MPMCS_RC_OK, "SINIT");

    TEST_RC(mpmcs_strace(scb, dump, 8), 8, "STRACE short");

    TEST_RC(mpmcs_strace(scb, dump, DUMP_N),
            MPMCS_RC_OK, "STRACE quiet");
    next0 = *(uint32_t *)(dump + 0);
    n     = *(uint32_t *)(dump + 4);
    mask  = *(uint32_t *)(dump + 8);
    slot  = *(uint32_t *)(dump + 12);
    TEST_EXPECT(n == 256, "ring n");
    TEST_EXPECT(slot == 32, "slot size");
    TEST_EXPECT(mask == 0, "default mask");
    TEST_EXPECT(next0 == 0, "silent next");

    TEST_RC(mpmcs_spush(scb, "aa", 2), MPMCS_RC_OK,
            "push quiet");
    TEST_RC(mpmcs_strace(scb, dump, DUMP_N),
            MPMCS_RC_OK, "STRACE after quiet push");
    TEST_EXPECT(*(uint32_t *)dump == next0, "mask0 freeze");

    TEST_RC(mpmcs_straceset(scb, MPMCS_TRC_ALL),
            MPMCS_RC_OK, "STRACESET all");

    TEST_RC(mpmcs_spush(scb, "bb", 2), MPMCS_RC_OK, "push 1");
    TEST_RC(mpmcs_spush(scb, "cc", 2), MPMCS_RC_OK, "push 2");
    TEST_RC(mpmcs_spush(scb, "dd", 2), MPMCS_RC_OK, "push 3");
    TEST_RC(mpmcs_spop(scb, out, sizeof(out), &len),
            MPMCS_RC_OK, "pop 1");
    TEST_RC(mpmcs_spop(scb, out, sizeof(out), &len),
            MPMCS_RC_OK, "pop 2");
    TEST_RC(mpmcs_spop(scb, out, sizeof(out), &len),
            MPMCS_RC_OK, "pop 3");
    TEST_RC(mpmcs_spop(scb, out, sizeof(out), &len),
            MPMCS_RC_EMPTY, "pop empty");

    TEST_RC(mpmcs_strace(scb, dump, DUMP_N),
            MPMCS_RC_OK, "STRACE armed");
    next1 = *(uint32_t *)(dump + 0);
    n     = *(uint32_t *)(dump + 4);
    mask  = *(uint32_t *)(dump + 8);
    TEST_EXPECT(next1 > next0, "events recorded");
    TEST_EXPECT(mask == MPMCS_TRC_ALL, "mask all");
    ring = dump + 16;
    npush = count_ev(ring, next1, n,
                     MPMCS_TRC_API, MPMCS_TRE_SPUSH);
    TEST_EXPECT(npush >= 3, "TRE_SPUSH");
    TEST_EXPECT(count_ev(ring, next1, n,
                MPMCS_TRC_API, MPMCS_TRE_SPOP) >= 4,
                "TRE_SPOP");
    TEST_EXPECT(count_ev(ring, next1, n,
                MPMCS_TRC_API, MPMCS_TRE_SPOPX) >= 4,
                "TRE_SPOPX");
    TEST_EXPECT(count_ev(ring, next1, n,
                MPMCS_TRC_CDS, MPMCS_TRE_CDSOK) >= 1,
                "TRE_CDSOK");

    TEST_RC(mpmcs_straceset(scb, 0), MPMCS_RC_OK, "mask 0");
    TEST_RC(mpmcs_spush(scb, "ee", 2), MPMCS_RC_OK, "push off");
    TEST_RC(mpmcs_strace(scb, dump, DUMP_N),
            MPMCS_RC_OK, "STRACE after off");
    TEST_EXPECT(*(uint32_t *)dump == next1, "off freeze");

    TEST_RC(mpmcs_scbstop(scb), MPMCS_RC_OK, "SCBSTOP");
    mpmcs_free(scb);

    scb = mpmcs_alloc_scb();
    TEST_EXPECT(scb != NULL, "SCB2 alloc failed");
    TEST_RC(mpmcs_sinit(scb,
            MPMCS_NODE_PREFILL(4) | MPMCS_OPT_TRACE,
            0, 0, 0),
            MPMCS_RC_OK, "SINIT TRACE");
    TEST_RC(mpmcs_strace(scb, dump, DUMP_N),
            MPMCS_RC_OK, "STRACE opt");
    TEST_EXPECT(*(uint32_t *)(dump + 8) == MPMCS_TRC_ALL,
                "OPT_TRACE mask");
    TEST_EXPECT(*(uint32_t *)dump > 0, "SINIT traced");
    TEST_RC(mpmcs_scbstop(scb), MPMCS_RC_OK, "SCBSTOP2");

    printf("T15TRACE PASS next=%u push=%d\n",
           (unsigned)next1, npush);
    mpmcs_free(dump);
    mpmcs_free(scb);
    return 0;
}
