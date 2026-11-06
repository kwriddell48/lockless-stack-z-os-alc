         TITLE 'MPMC stack - Storage helpers (IARV64 payload)'
***********************************************************************
*  STORAGE.ASM
*
*  64-bit payload allocation/free when SINIT selected
* MPMCS_OPT_PAYLOAD64.
*
*  Performance: these are LEAF routines. They reuse the caller's work
* cell
*  (R13) at WK_IARV for the IARV64 MF=E parameter list - no OBTAIN
* here.
*
*  Caller must have entered via MPMCQ_ENTER_SCB (or equivalent) so
* that:
*    - R13 -> work cell with at least WK_IARV+WK_IARVMAX bytes
*    - a next save area is available for our STM
*
*  MPMCS_PAYGET  In: R7=len   Out: R15=0/8, R8=addr64
*  MPMCS_PAYFREE In: R8=addr64, R7=len  Out: R15=0
*
*  IARV64 (SYS1.MACLIB):
*    GETSTOR requires SEGMENTS= or UNITS= (size in megabytes), not
*    LENGTH=. ORIGIN= is the address of an AD that receives the
*    object start. Free is REQUEST=DETACH,MEMOBJSTART= (address of
*    that AD). MF=E builds the plist in the work cell (XC 88 bytes);
*    do not use MF=L with REQUEST= (only PLISTVER is allowed on L).
*    Byte length is rounded up to whole MB segments.
***********************************************************************

         PRINT GEN

         COPY  REGEQUAT
         COPY  SAVEMAC

MPMCQSTO CSECT
MPMCQSTO AMODE 31
MPMCQSTO RMODE ANY

         ENTRY MPMCS_PAYGET
         ENTRY MPMCS_PAYFREE

         USING MPMCQSTO,R15

* Must match offsets in src/mpmcq.asm work-cell layout.
WK_IARV    EQU   128
WK_IARVMAX EQU   256
* AD: GETSTOR SEGMENTS input (MB count)
WK_SEG     EQU   384
* AD: GETSTOR ORIGIN out / DETACH MEMOBJSTART in
WK_ORIG    EQU   392

***********************************************************************
* MPMCS_PAYGET
***********************************************************************
MPMCS_PAYGET DS 0H
         STM   R14,R12,12(R13)
         LARL  R12,MPMCQSTO
         DROP  R15
         USING MPMCQSTO,R12

         LTR   R7,R7
         JNZ   PAYGET_DO
         XR    R8,R8
         XR    R15,R15
         MPMCQ_LEAF_RETURN_R8 R15

PAYGET_DO DS 0H
* Bytes in R7 -> 64-bit MB count at WK_SEG (ceil, min 1).
         LLGFR R6,R7
         ALGFI R6,X'000FFFFF'
         SRLG  R6,R6,20
         STG   R6,WK_SEG(,R13)
* MF=E XC's the 88-byte plist at (R1); work cell is the list.
         LA    R1,WK_IARV(,R13)
         LA    R5,WK_SEG(,R13)
         LA    R4,WK_ORIG(,R13)
         IARV64 REQUEST=GETSTOR,COND=YES,SEGMENTS=(R5),                X
               ORIGIN=(R4),MF=(E,(R1))
         LTR   R15,R15
         JZ    PAYGET_OK
         LA    R15,8
         MPMCQ_LEAF_RETURN R15

PAYGET_OK DS 0H
         LG    R8,WK_ORIG(,R13)
         XR    R15,R15
         MPMCQ_LEAF_RETURN_R8 R15

***********************************************************************
* MPMCS_PAYFREE
***********************************************************************
MPMCS_PAYFREE DS 0H
         STM   R14,R12,12(R13)
         LARL  R12,MPMCQSTO
         USING MPMCQSTO,R12

         LTR   R7,R7
         JZ    PAYFREE_DONE

         STG   R8,WK_ORIG(,R13)
         LA    R1,WK_IARV(,R13)
         LA    R4,WK_ORIG(,R13)
         IARV64 REQUEST=DETACH,COND=YES,MEMOBJSTART=(R4),              X
               MF=(E,(R1))

PAYFREE_DONE DS 0H
         XR    R15,R15
         MPMCQ_LEAF_RETURN R15

         LTORG
         END   MPMCQSTO
