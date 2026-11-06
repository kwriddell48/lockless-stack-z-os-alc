/* T01VER - GETVERSION copies the assemble-time build string. */
#include "mpmcs.h"

int main(void)
{
    char buf[80];
    char tiny[8];
    uint32_t act = 0;
    int32_t rc;

    printf("T01VER start\n");
    fflush(stdout);

    memset(buf, 0, sizeof(buf));
    rc = mpmcs_getversion(buf, (uint32_t)sizeof(buf) - 1, &act);
    TEST_RC(rc, MPMCS_RC_OK, "GETVERSION");
    TEST_EXPECT(act > 0, "version length is 0");
    TEST_EXPECT(act < sizeof(buf), "version longer than buffer");
    TEST_EXPECT(memcmp(buf, "MPMC", 4) == 0, "version prefix not MPMC");

    printf("version len=%u text=%.*s\n", (unsigned)act, (int)act, buf);

    act = 0;
    memset(tiny, 0, sizeof(tiny));
    rc = mpmcs_getversion(tiny, 4, &act);
    TEST_RC(rc, MPMCS_RC_TRUNC, "GETVERSION truncated");
    TEST_EXPECT(act > 4, "truncated call did not report full length");

    printf("T01VER PASS\n");
    return 0;
}
