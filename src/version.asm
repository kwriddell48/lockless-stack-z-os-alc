         TITLE 'MPMC stack - GETVERSION (product build/version string)'
***********************************************************************
*  VERSION.ASM
***********************************************************************

         PRINT GEN

         COPY  REGEQUAT
         COPY  DSECTS
         COPY  SAVEMAC

MPMCQVER CSECT
MPMCQVER AMODE 31
MPMCQVER RMODE ANY

         ENTRY GETVERSION
         USING MPMCQVER,R15

VER_STR  DC    C'MPMC stack build &SYSDATE &SYSTIME'
VER_END  DS    0C
VER_LEN  EQU   VER_END-VER_STR

GV_WLEN  EQU   72                          save area only

GETVERSION DS 0H
         MPMCQ_ENTER GV_WLEN,MPMCQVER
         USING MPMCQVER,R12
         USING MPMCS_GETVER_PLIST,R1

         LT    R3,GVER_OUTADDR
         L     R4,GVER_OUTMAX

         JNZ   GV_DO_COPY
         LA    R1,VER_STR
         LA    R0,VER_LEN
         XR    R15,R15
         MPMCQ_RETURN_R01 R15,GV_WLEN

GV_DO_COPY DS 0H
         LT    R5,GVER_OUTACTLENADDR
         JZ    GV_LEN_DONE
         LA    R0,VER_LEN
         ST    R0,0(R5)
GV_LEN_DONE DS 0H

         LA    R0,VER_LEN
         LR    R6,R0
         CLR   R4,R6
         JNL   GV_FITS
         LR    R6,R4
         LA    R7,8
         J     GV_HAVE_LEN
GV_FITS  DS 0H
         XR    R7,R7
GV_HAVE_LEN DS 0H

         LR    R8,R3
         LR    R9,R6
         LA    R10,VER_STR
         LR    R11,R6
         MVCL  R8,R10

         LR    R15,R7
         MPMCQ_RETURN R15,GV_WLEN

         LTORG
         END   MPMCQVER
