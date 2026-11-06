/* T07STATS - SSTATS counters track push, pop, empty, and depth. */
#include "mpmcs.h"

int main(void)
{
    void *scb;
    char out[8];
    uint32_t n = 0;
    MpmcsStats st;

    printf("T07STATS start\n");
    fflush(stdout);

    scb = mpmcs_alloc_scb();
    TEST_EXPECT(scb != NULL, "SCB alloc failed");
    TEST_RC(mpmcs_sinit(scb, MPMCS_OPT_PAYLOAD31, 0, 0, 0),
            MPMCS_RC_OK, "SINIT");

    TEST_RC(mpmcs_spop(scb, out, sizeof(out), &n),
            MPMCS_RC_EMPTY, "empty pop");
    TEST_RC(mpmcs_spush(scb, "ab", 2), MPMCS_RC_OK, "push 1");
    TEST_RC(mpmcs_spush(scb, "cd", 2), MPMCS_RC_OK, "push 2");
    TEST_RC(mpmcs_spop(scb, out, sizeof(out), &n), MPMCS_RC_OK, "pop");

    TEST_RC(mpmcs_sstats(scb, &st), MPMCS_RC_OK, "SSTATS");
    TEST_EXPECT(st.version == MPMCS_STATS_VERSION, "stats version");
    TEST_EXPECT(st.size >= 16, "stats size");
    TEST_EXPECT(st.push_ok == 2, "push_ok");
    TEST_EXPECT(st.pop_ok == 1, "pop_ok");
    TEST_EXPECT(st.pop_empty == 1, "pop_empty");
    TEST_EXPECT(st.depth_cur == 1, "depth_cur");
    TEST_EXPECT(st.depth_max >= 2, "depth_max");
    TEST_EXPECT(st.payload31_cur == 2, "payload31_cur after one pop");
    TEST_EXPECT(st.payload31_max >= 4, "payload31_max");
    TEST_EXPECT(st.payload64_cur == 0 && st.payload64_max == 0,
                "payload64 should be unused");

    printf("push_ok=%u pop_ok=%u empty=%u depth=%u/%u p31=%llu/%llu\n",
           (unsigned)st.push_ok, (unsigned)st.pop_ok,
           (unsigned)st.pop_empty,
           (unsigned)st.depth_cur, (unsigned)st.depth_max,
           (unsigned long long)st.payload31_cur,
           (unsigned long long)st.payload31_max);

    TEST_RC(mpmcs_scbstop(scb), MPMCS_RC_OK, "SCBSTOP");
    printf("T07STATS PASS\n");
    mpmcs_free(scb);
    return 0;
}
