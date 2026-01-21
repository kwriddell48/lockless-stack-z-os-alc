         TITLE 'MPMC stack user API include (entry points + parm lists)'
***********************************************************************
*  MPMCS_USER.INC
*
*  User-facing include for calling the MPMC stack entry points.
*
*  This file is safe to COPY into an assembler caller.
*  It defines:
*    - option bits
*    - SCB and stats layouts (for sizing/caller storage)
*    - parameter list DSECTs (R1 -> parm list)
*    - callback parm list DSECT
*
*  Entry points (external):
*    SINIT     - initialize a stack control block (SCB)
*    SPUSH     - push a record (copies bytes in)
*    SPOP      - pop a record (copies bytes out)
*    SSTATS    - copy a stats snapshot
*    SCBSTOP   - stop notifier TCB (optional)
*    GETVERSION- get build/version string
*
*  Return codes:
*    SPUSH:  0 success, 8 allocation failure
*    SPOP:   4 empty, 0 success, 8 truncated
*
*  Note:
*    These routines use standard z/OS linkage: R1 -> parameter list.
***********************************************************************

***********************************************************************
* Public entry point names (for EXTRN)
***********************************************************************
MPMCS_API_EQUATES        EQU   *
SINIT                   EQU   SINIT
SPUSH                   EQU   SPUSH
SPOP                    EQU   SPOP
SSTATS                  EQU   SSTATS
SCBSTOP                 EQU   SCBSTOP
GETVERSION              EQU   GETVERSION

***********************************************************************
* Options
***********************************************************************
MPMCS_OPT_PAYLOAD31      EQU   X'00000000'  * default: payload allocated below 2G
MPMCS_OPT_PAYLOAD64      EQU   X'00000001'  * payload allocated in 64-bit storage

***********************************************************************
* Stack Control Block (SCB) and stats layouts
* (Caller normally allocates these as plain storage; fields are documented.)
***********************************************************************
MPMCS_STATS_VERSION    EQU   1

***********************************************************************
* Stack Control Block (SCB)
***********************************************************************
MPMCS_SCB              DSECT
SCB_EYECATCH           DS    CL8               'MPMCSTK '
SCB_NAME               DS    CL16              user-assigned stack name
SCB_VERSION            DS    F                 version
SCB_FLAGS              DS    F                 runtime flags

* Ensure tagged pointers are doubleword aligned for CDS.
SCB_ALIGN0             DS    0D

* Tagged pointer: (ABA32, PTR31)
SCB_TOP_ABA            DS    F                 ABA tag
SCB_TOP_PTR            DS    F                 ptr to top node (31-bit)

* Node freelist head (tagged pointer)
SCB_FREE_ABA           DS    F                 ABA tag
SCB_FREE_PTR           DS    F                 ptr to free node

* Async callback fields
SCB_CB_EP              DS    F                 callback entry point (AMODE 31)
SCB_CB_CTX             DS    F                 user context pointer (31-bit)
SCB_USER_ECB           DS    F                 optional user ECB to POST per PUSH

* Internal notifier support
SCB_CB_ECB             DS    F                 internal ECB (fullword)
SCB_PUSH_SEQ           DS    F                 push sequence (monotonic)
SCB_CB_SEQ_SEEN        DS    F                 last processed by notifier
SCB_CB_TCB             DS    F                 notifier TCB addr (optional)
SCB_ABA_SEQ            DS    F                 global ABA tag generator (monotonic)

***********************************************************************
* Stats (kept in SCB; returned via SSTATS)
***********************************************************************
SCB_STAT_ALIGN         DS    0D

SCB_STAT_PUSH_OK       DS    F
SCB_STAT_POP_OK        DS    F
SCB_STAT_POP_EMPTY     DS    F
SCB_STAT_PUSH_ALLOC_FAIL DS  F

SCB_STAT_PUSH_RETRY    DS    F
SCB_STAT_POP_RETRY     DS    F
SCB_STAT_FREELIST_POP_RETRY DS F
SCB_STAT_FREELIST_PUSH_RETRY DS F

SCB_STAT_DEPTH_CUR     DS    F                 best-effort
SCB_STAT_DEPTH_MAX     DS    F

* Payload byte usage (doubleword, updated via CDS loops)
SCB_STAT_PAYLOAD31_CUR_HI DS  F
SCB_STAT_PAYLOAD31_CUR_LO DS  F
SCB_STAT_PAYLOAD31_MAX_HI DS  F
SCB_STAT_PAYLOAD31_MAX_LO DS  F

SCB_STAT_PAYLOAD64_CUR_HI DS  F
SCB_STAT_PAYLOAD64_CUR_LO DS  F
SCB_STAT_PAYLOAD64_MAX_HI DS  F
SCB_STAT_PAYLOAD64_MAX_LO DS  F

SCB_STAT_POST_INTERNAL DS   F
SCB_STAT_POST_USERECB  DS   F
SCB_STAT_CB_CALLS      DS   F
SCB_STAT_CB_PENDING_MAX DS  F

SCB_SIZE               EQU   *-MPMCS_SCB

***********************************************************************
* SSTATS snapshot layout (caller buffer)
***********************************************************************
MPMCS_STATS              DSECT
STATS_VERSION            DS   F
STATS_SIZE               DS   F                 bytes copied

STATS_PUSH_OK            DS   F
STATS_POP_OK             DS   F
STATS_POP_EMPTY          DS   F
STATS_PUSH_ALLOC_FAIL    DS   F

STATS_PUSH_RETRY         DS   F
STATS_POP_RETRY          DS   F
STATS_FREELIST_POP_RETRY DS   F
STATS_FREELIST_PUSH_RETRY DS  F

STATS_DEPTH_CUR          DS   F
STATS_DEPTH_MAX          DS   F

STATS_PAYLOAD31_CUR      DS   D
STATS_PAYLOAD31_MAX      DS   D

STATS_PAYLOAD64_CUR      DS   D
STATS_PAYLOAD64_MAX      DS   D

STATS_POST_INTERNAL      DS   F
STATS_POST_USERECB       DS   F
STATS_CB_CALLS           DS   F
STATS_CB_PENDING_MAX     DS   F

STATS_RSVD               DS   0D
STATS_END                EQU  *

***********************************************************************
* Parameter lists (R1 -> parm list)
***********************************************************************

* SINIT(SCBaddr, options, CB_EP, CB_CTX, USER_ECB)
MPMCS_SINIT_PLIST       DSECT
SINIT_SCBADDR           DS   F
SINIT_OPTIONS           DS   F
SINIT_CB_EP             DS   F
SINIT_CB_CTX            DS   F
SINIT_USER_ECB          DS   F

* SPUSH(SCBaddr, srcAddr, srcLen)
MPMCS_SPUSH_PLIST       DSECT
SPU_SCBADDR             DS   F
SPU_SRCADDR             DS   F
SPU_SRCLEN              DS   F

* SPOP(SCBaddr, dstAddr, dstMaxLen, outLenAddr)
MPMCS_SPOP_PLIST        DSECT
SPO_SCBADDR             DS   F
SPO_DSTADDR             DS   F
SPO_DSTMAX              DS   F
SPO_OUTLENADDR          DS   F

* SSTATS(SCBaddr, outStatsAddr, outStatsLen)
MPMCS_SSTATS_PLIST      DSECT
SST_SCBADDR             DS   F
SST_OUTADDR             DS   F
SST_OUTLEN              DS   F

* GETVERSION(outAddr, outMaxLen, outActLenAddr)
MPMCS_GETVER_PLIST      DSECT
GVER_OUTADDR            DS   F
GVER_OUTMAX             DS   F
GVER_OUTACTLENADDR      DS   F

* Callback parm list: (CB_CTX, SCBaddr, PendingCount)
MPMCQ_CB_PLIST          DSECT
CBP_CTX                 DS   F
CBP_SCB                 DS   F
CBP_PENDING             DS   F

***********************************************************************
* Example (assembler) - initialize + push + pop
*
*         EXTRN SINIT,SPUSH,SPOP
*         COPY  'include/mpmcs_user.inc'
*
*SCB      DS    0D
*         DS    CL(SCB_SIZE)
*
*SINITPL  DS    0F
*         DS    (SINIT_USER_ECB+4)X
*
*         LA    R2,SCB
*         LA    R1,SINITPL
*         ST    R2,SINIT_SCBADDR(R1)
*         MVC   SINIT_OPTIONS(R1),=F'MPMCS_OPT_PAYLOAD64'
*         MVC   SINIT_CB_EP(R1),=F'0'
*         MVC   SINIT_CB_CTX(R1),=F'0'
*         MVC   SINIT_USER_ECB(R1),=F'0'
*         L     R15,=V(SINIT)
*         BALR  R14,R15
*
*         ... build SPUSH parm list and call SPUSH ...
***********************************************************************

