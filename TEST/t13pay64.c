/* T13PAY64 - 64-bit payload path (IARV64 GETSTOR, 1MB per message). */
#include "mpmcs.h"

int main(void)
{
    void *scb;
    char out[32];
    uint32_t n = 0;
    int32_t rc;
    MpmcsStats st;
    const char *msg = "above-the-bar";

    printf("T13PAY64 start\n");
    fflush(stdout);

    scb = mpmcs_alloc_scb();
    TEST_EXPECT(scb != NULL, "SCB alloc failed");
    TEST_RC(mpmcs_sinit(scb, MPMCS_OPT_PAYLOAD64, 0, 0, 0),
            MPMCS_RC_OK, "SINIT PAYLOAD64");

    rc = mpmcs_spush(scb, msg, (uint32_t)strlen(msg));
    if (rc == MPMCS_RC_ALLOC_FAIL) {
        fprintf(stderr,
                "T13PAY64 SKIP: IARV64 GETSTOR rc=8 "
                "(MEMLIMIT / authorization)\n");
        mpmcs_scbstop(scb);
        mpmcs_free(scb);
        return 4;
    }
    TEST_RC(rc, MPMCS_RC_OK, "push 64-bit payload");

    TEST_RC(mpmcs_spush(scb, "2", 1), MPMCS_RC_OK, "push 2");

    memset(out, 0, sizeof(out));
    rc = mpmcs_spop(scb, out, sizeof(out), &n);
    TEST_RC(rc, MPMCS_RC_OK, "pop 2");
    TEST_EXPECT(n == 1 && out[0] == '2', "LIFO under PAYLOAD64");

    memset(out, 0, sizeof(out));
    rc = mpmcs_spop(scb, out, sizeof(out), &n);
    TEST_RC(rc, MPMCS_RC_OK, "pop msg");
    TEST_EXPECT(n == (uint32_t)strlen(msg), "len");
    TEST_EXPECT(memcmp(out, msg, n) == 0, "payload bytes");

    TEST_RC(mpmcs_sstats(scb, &st), MPMCS_RC_OK, "SSTATS");
    TEST_EXPECT(st.payload31_cur == 0, "payload31 unused");
    TEST_EXPECT(st.payload64_max > 0, "payload64_max");
    TEST_EXPECT(st.payload64_cur == 0, "payload64_cur after drain");

    printf("payload64_max=%llu push_ok=%u\n",
           (unsigned long long)st.payload64_max, (unsigned)st.push_ok);

    TEST_RC(mpmcs_scbstop(scb), MPMCS_RC_OK, "SCBSTOP");
    printf("T13PAY64 PASS\n");
    mpmcs_free(scb);
    return 0;
}
