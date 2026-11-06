         TITLE 'MPMC stack - Flight recorder dump and mask'
***********************************************************************
*  TRACE.ASM
*
*  STRACE(SCBaddr, outAddr, outLen)
*    Copy 16-byte header (NEXT,N,MASK,SLOT) plus as many ring
*    bytes as fit. RC=0, RC=4 if no ring, RC=8 if outLen < 16.
*    Writers publish STCKF last; a slot with TOD=0 may be in
*    flight or unused. Ring wrap can still overwrite live slots.
*  STRACESET(SCBaddr, mask)
*    Store class mask (0 = silent). Ring stays allocated.
***********************************************************************
         PRINT GEN
         COPY  REGEQUAT
         COPY  DSECTS
         COPY  SAVEMAC

MPMCQTR  CSECT
MPMCQTR  AMODE 31
MPMCQTR  RMODE ANY
         ENTRY STRACE
         ENTRY STRACESET
         USING MPMCQTR,R15

***********************************************************************
STRACE   DS    0H
         MPMCQ_ENTER_SCB MPMCQTR
         USING MPMCQTR,R12
         USING MPMCS_SCB,Q_R
         USING MPMCS_STRACE_PLIST,R1
         L     R6,STR_OUTADDR
         L     R7,STR_OUTLEN
         DROP  R1
         LTR   R6,R6
         JZ    STR_BAD
         CLFI  R7,TH_HDRLEN
         JL    STR_BAD
         LT    R8,SCB_TRC_BASE
         JZ    STR_NONE
         L     R0,SCB_TRC_NEXT
         ST    R0,0(,R6)
         L     R0,SCB_TRC_N
         ST    R0,4(,R6)
         L     R0,SCB_TRC_MASK
         ST    R0,8(,R6)
         LA    R0,MPMCS_TRC_SLOT
         ST    R0,12(,R6)
         S     R7,=F'16'
         L     R9,SCB_TRC_N
         SLL   R9,5
         CLR   R7,R9
         JNH   STR_LENOK
         LR    R7,R9
STR_LENOK DS   0H
         LTR   R7,R7
         JZ    STR_OK
         LA    R4,16(,R6)
         LR    R5,R7
         LR    R10,R8
         LR    R11,R7
         MVCL  R4,R10
STR_OK   DS    0H
         XR    R15,R15
         MPMCQ_RETURN_SCB R15
STR_NONE DS    0H
         LA    R15,4
         MPMCQ_RETURN_SCB R15
STR_BAD  DS    0H
         LA    R15,8
         MPMCQ_RETURN_SCB R15

***********************************************************************
STRACESET DS   0H
         MPMCQ_ENTER_SCB MPMCQTR
         USING MPMCQTR,R12
         USING MPMCS_SCB,Q_R
         USING MPMCS_STRSET_PLIST,R1
         L     R4,STRS_MASK
         DROP  R1
         ST    R4,SCB_TRC_MASK
         XR    R15,R15
         MPMCQ_RETURN_SCB R15

         LTORG
         END   MPMCQTR
