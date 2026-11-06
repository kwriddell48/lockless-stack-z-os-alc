/* T21BURST - variable-length bursts + truncated concurrent pops. */
#define _OPEN_THREADS 1
#include "mpmcs.h"

#ifdef __MVS__
#pragma runopts(POSIX(ON))
#endif

#include <pthread.h>

#define NPROD 4
#define NCONS 4
#define NBURST 100

typedef struct {
    void    *scb;
    int      id;
    uint32_t nfull;
    uint32_t ntrunc;
    int      rc;
} Worker;

static volatile int g_go;
static volatile int g_prod_done;

static void fill_body(unsigned char *b, uint32_t len, uint32_t seed)
{
    uint32_t i;
    for (i = 0; i < len; i++)
        b[i] = (unsigned char)((seed + i * 17u) & 0xFF);
}

static int check_body(const unsigned char *b, uint32_t n,
                      uint32_t seed)
{
    uint32_t i;
    for (i = 0; i < n; i++) {
        if (b[i] != (unsigned char)((seed + i * 17u) & 0xFF))
            return 0;
    }
    return 1;
}

static void *producer(void *arg)
{
    Worker *w = (Worker *)arg;
    unsigned char buf[200];
    uint32_t i;
    uint32_t len;
    uint32_t seed;

    while (!g_go)
        ;

    w->rc = 0;
    for (i = 0; i < NBURST; i++) {
        len = 12u + ((i * 17u + (uint32_t)w->id) % 170u);
        seed = ((uint32_t)w->id << 16) | i;
        memcpy(buf, &seed, 4);
        fill_body(buf + 4, len - 4, seed);
        if (mpmcs_spush(w->scb, buf, len) != MPMCS_RC_OK) {
            w->rc = 8;
            return 0;
        }
    }
    return 0;
}

static void *consumer(void *arg)
{
    Worker *w = (Worker *)arg;
    unsigned char buf[200];
    uint32_t n;
    uint32_t dstmax;
    uint32_t got;
    uint32_t seed;
    int32_t rc;
    unsigned idle = 0;

    while (!g_go)
        ;

    w->nfull = 0;
    w->ntrunc = 0;
    w->rc = 0;
    for (;;) {
        dstmax = ((w->nfull + w->ntrunc) & 1u) ? 16u : 200u;
        n = 0;
        rc = mpmcs_spop(w->scb, buf, dstmax, &n);
        if (rc == MPMCS_RC_OK || rc == MPMCS_RC_TRUNC) {
            idle = 0;
            if (n < 12u) {
                w->rc = 8;
                return 0;
            }
            got = (n < dstmax) ? n : dstmax;
            if (rc == MPMCS_RC_OK && got != n) {
                w->rc = 8;
                return 0;
            }
            if (rc == MPMCS_RC_TRUNC) {
                if (got != dstmax || n <= dstmax) {
                    w->rc = 8;
                    return 0;
                }
            }
            if (got >= 4) {
                memcpy(&seed, buf, 4);
                if (!check_body(buf + 4, got - 4, seed)) {
                    w->rc = 8;
                    return 0;
                }
            }
            if (rc == MPMCS_RC_OK)
                w->nfull++;
            else
                w->ntrunc++;
            continue;
        }
        if (rc != MPMCS_RC_EMPTY) {
            w->rc = 8;
            return 0;
        }
        if (g_prod_done) {
            if (++idle > 80000u)
                break;
        }
        mpmcs_spin(40u);
    }
    return 0;
}

int main(void)
{
    void *scb;
    pthread_t tp[NPROD];
    pthread_t tc[NCONS];
    Worker prod[NPROD];
    Worker cons[NCONS];
    MpmcsStats st;
    unsigned char dump[8];
    uint32_t n = 0;
    uint32_t pops = 0;
    uint32_t truncs = 0;
    int32_t rc;
    int i;

    printf("T21BURST start prod=%d cons=%d burst=%d\n",
           NPROD, NCONS, NBURST);
    fflush(stdout);

    scb = mpmcs_alloc_scb();
    TEST_EXPECT(scb != NULL, "SCB alloc");
    TEST_RC(mpmcs_sinit(scb,
            MPMCS_NODE_PREFILL(256) | MPMCS_OPT_PAYLOAD31,
            0, 0, 0),
            MPMCS_RC_OK, "SINIT");

    g_go = 0;
    g_prod_done = 0;
    for (i = 0; i < NCONS; i++) {
        cons[i].scb = scb;
        cons[i].id = i;
        if (pthread_create(&tc[i], 0, consumer, &cons[i]) != 0)
            TEST_FAIL("cons create");
    }
    for (i = 0; i < NPROD; i++) {
        prod[i].scb = scb;
        prod[i].id = i;
        if (pthread_create(&tp[i], 0, producer, &prod[i]) != 0)
            TEST_FAIL("prod create");
    }
    g_go = 1;
    for (i = 0; i < NPROD; i++)
        pthread_join(tp[i], 0);
    g_prod_done = 1;
    for (i = 0; i < NCONS; i++)
        pthread_join(tc[i], 0);

    for (i = 0; i < NPROD; i++)
        TEST_EXPECT(prod[i].rc == 0, "prod rc");
    for (i = 0; i < NCONS; i++) {
        TEST_EXPECT(cons[i].rc == 0, "cons rc");
        pops += cons[i].nfull + cons[i].ntrunc;
        truncs += cons[i].ntrunc;
    }

    for (;;) {
        n = 0;
        rc = mpmcs_spop(scb, dump, sizeof(dump), &n);
        if (rc == MPMCS_RC_OK || rc == MPMCS_RC_TRUNC) {
            pops++;
            if (rc == MPMCS_RC_TRUNC)
                truncs++;
            continue;
        }
        break;
    }

    TEST_RC(mpmcs_sstats(scb, &st), MPMCS_RC_OK, "SSTATS");
    TEST_EXPECT(st.push_ok == (uint32_t)(NPROD * NBURST),
                "push_ok");
    TEST_EXPECT(st.pop_ok == st.push_ok, "pop_ok");
    TEST_EXPECT(st.depth_cur == 0, "depth");
    TEST_EXPECT(pops == st.pop_ok, "pop tally");
    TEST_EXPECT(truncs >= 1, "saw truncation");

    printf("push=%u pops=%u truncs=%u dmax=%u\n",
           (unsigned)st.push_ok, (unsigned)pops,
           (unsigned)truncs, (unsigned)st.depth_max);

    TEST_RC(mpmcs_scbstop(scb), MPMCS_RC_OK, "SCBSTOP");
    printf("T21BURST PASS\n");
    mpmcs_free(scb);
    return 0;
}
