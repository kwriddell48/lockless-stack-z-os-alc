         TITLE 'MPMC stack user include (API + examples)'
***********************************************************************
*  user_api.inc
*
*  Single-file user include for calling the MPMC stack entry points.
*
*  This include provides:
*    - Public entry point names
*    - Option and return-code equates
*    - SCB layout + SCB_SIZE (for caller allocation)
*    - Stats snapshot layout (for SSTATS output)
*    - Parameter list layouts (R1 -> parm list)
*    - Callback parm list layout
*    - Examples (assembler-style and C-style)
*
*  Notes:
*    - Caller runs AMODE 31 and passes a standard parameter list at R1.
*    - SCB storage must be below-the-bar (31-bit addressable).
*    - The SCB is caller-owned control-block storage and must remain
*      allocated/valid for the full lifetime of the stack instance
*      (from SINIT until you stop using that SCB with SPUSH/SPOP/SSTATS/SCBSTOP).
***********************************************************************
***********************************************************************
* Public entry points (external names)
***********************************************************************
SINIT                   EQU   SINIT
SPUSH                   EQU   SPUSH
SPOP                    EQU   SPOP
SSTATS                  EQU   SSTATS
SCBSTOP                 EQU   SCBSTOP
GETVERSION              EQU   GETVERSION
***********************************************************************
* Options (SINIT OPTIONS)
*   bit 0      = payload mode (31 vs 64)
*   bits 0-15 = node prefill count (0 = default MPMCS_NODE_PREFILL)
*   bit 31    = MPMCS_OPT_PAYLOAD64 (X'00000001')
*   Example:  (64)*65536+MPMCS_OPT_PAYLOAD64
***********************************************************************
MPMCS_OPT_PAYLOAD31      EQU   X'00000000'  * default: payload below 2G
MPMCS_OPT_PAYLOAD64      EQU   X'00000001'  * payload in 64-bit storage (IARV64)
MPMCS_NODE_PREFILL       EQU   64           * default nodes onto freelist at SINIT
MPMCS_WORK_PREFILL       EQU   16           * default work cells at SINIT
MPMCS_WORK_CELL          EQU   512          * fixed work-cell size (ENTER_SCB)
***********************************************************************
* Return codes
***********************************************************************
MPMCS_RC_OK              EQU   0
MPMCS_RC_EMPTY           EQU   4
MPMCS_RC_TRUNC           EQU   8
MPMCS_RC_ALLOC_FAIL      EQU   8
***********************************************************************
* Layouts (SCB, stats snapshot, parm lists)
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
* Work-cell freelist (SPUSH/SPOP save areas — performance pool)
SCB_WORK_ABA           DS    F
SCB_WORK_PTR           DS    F
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
* Assembler call examples (outline)
***********************************************************************
* Example: initialize (SINIT)
*
*         EXTRN SINIT
*         COPY  'user_api.inc'
*
*SCB      DS    0D
*         DS    CL(SCB_SIZE)
*
*SINITPL  DS    0F
*         DS    (SINIT_USER_ECB+4)X
*
*         LA    R1,SINITPL
*         LA    R2,SCB
*         ST    R2,SINIT_SCBADDR(R1)
*         MVC   SINIT_OPTIONS(R1),=F'MPMCS_OPT_PAYLOAD64'
*         MVC   SINIT_CB_EP(R1),=F'0'
*         MVC   SINIT_CB_CTX(R1),=F'0'
*         MVC   SINIT_USER_ECB(R1),=F'0'
*         L     R15,=V(SINIT)
*         BALR  R14,R15
*         * R15=0 on success
*
***********************************************************************
* C-style call examples (illustrative)
***********************************************************************
* Example:
*
*   void* scb = ...;   // below-the-bar storage, size SCB_SIZE
*   int rc = SINIT(scb, MPMCS_OPT_PAYLOAD64, 0, 0, 0);
*   rc = SPUSH(scb, msg, msg_len);
*   rc = SPOP(scb, out, out_max, &actual_len);
*   rc = SSTATS(scb, &stats, sizeof(stats));
*
***********************************************************************

