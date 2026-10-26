;
; touch - Set the modification date and time of a ProDOS file to now
;
; For the Apple II under ProDOS 8. Assemble with ca65 (cc65 suite).
;
; Usage (from BASIC.SYSTEM):
;
;     ]-TOUCH
;     FILE TO TOUCH:MYFILE
;     TOUCHED MYFILE 26-OCT-26 14:05
;
; The pathname may be partial (relative to the current prefix) or a
; full pathname such as /VOLUME/DIR/FILE. Like Unix touch, a file that
; does not exist is created (as an empty TXT file). Pressing RETURN on
; an empty line exits without doing anything.
;
; The current date and time come from the ProDOS GET_TIME call, which
; reads the clock card (if any) into the global page. If there is no
; clock and no date has been set, touch asks for one:
;
;     NO DATE IS SET. ENTER TODAY'S DATE AS
;     DD-MON-YY OR DD-MON-YY HH:MM
;     DATE:26-OCT-26 14:05
;     TOUCHED MYFILE 26-OCT-26 14:05
;
; The date goes into the ProDOS global page, so ProDOS uses it from then
; on, and then onto the file. Without a time, the time is set to 00:00.
; An empty line cancels, changing nothing.
;

        .setcpu "6502"

; ProDOS MLI and global page
MLI             = $BF00
DATE            = $BF90         ; date: lo = MMMDDDDD, hi = YYYYYYYM
TIME            = $BF92         ; time: lo = minute, hi = hour

GET_TIME_CMD    = $82
CREATE_CMD      = $C0
SET_INFO_CMD    = $C3
GET_INFO_CMD    = $C4
ON_LINE_CMD     = $C5
GET_PREFIX_CMD  = $C7

ERR_INVALID_PATH   = $40
ERR_FILE_NOT_FOUND = $46

; BASIC.SYSTEM global page
DEFSLT          = $BE3C         ; default slot
DEFDRV          = $BE3D         ; default drive

; Monitor
PROMPT          = $33           ; prompt character for GETLN
INBUF           = $0200         ; GETLN input buffer
GETLN           = $FD6A
CROUT           = $FD8E
PRBYTE          = $FDDA
COUT            = $FDED

; Zero page
PTR             = $06           ; free for user programs

MAXPATH         = 64            ; longest ProDOS pathname
CR              = $0D

; Print the zero terminated string at addr
.macro  PRINT   addr
        lda     #<addr
        ldy     #>addr
        jsr     print
.endmacro

        .segment "CODE"

start:
        lda     #<msg_prompt    ; ask for the pathname
        ldy     #>msg_prompt
        jsr     input
        jsr     parse_path
        bcc     @parsed
        PRINT   msg_too_long
        rts
@parsed:
        lda     path
        bne     @get_time
        rts                     ; empty line: nothing to do

@get_time:
        ; Read the clock into DATE/TIME on the global page
        jsr     MLI
        .byte   GET_TIME_CMD
        .word   0
        lda     DATE
        ora     DATE+1
        bne     @get_info
        jsr     ask_date        ; no clock and no date: ask for one
        bcc     @get_info
        rts                     ; cancelled

@get_info:
        jsr     resolve_path
        bcs     error
        jsr     get_info
        bcc     @touch
        cmp     #ERR_FILE_NOT_FOUND
        bne     error

        ; No such file: create it, as Unix touch does
        jsr     MLI
        .byte   CREATE_CMD
        .word   create_parms
        bcs     error
        lda     #<msg_created
        ldy     #>msg_created
        sta     verb
        sty     verb+1
        jsr     get_info
        bcs     error

@touch:
        ; Reuse the GET_FILE_INFO results (access, type, aux type) and
        ; replace only the modification date and time
        ldx     #3
@copy:  lda     DATE,x
        sta     info_mod_date,x
        dex
        bpl     @copy

        lda     #7              ; SET_FILE_INFO takes 7 parameters
        sta     info_parms
        jsr     MLI
        .byte   SET_INFO_CMD
        .word   info_parms
        bcs     error

        ; Report what was done: "TOUCHED PATH DD-MON-YY HH:MM"
        lda     verb
        ldy     verb+1
        jsr     print
        jsr     print_path
        lda     #' ' | $80
        jsr     COUT
        jsr     print_timestamp
        jmp     CROUT

; Print "ERROR $xx" and a description for the MLI error code in A
error:
        pha
        PRINT   msg_error
        pla
        pha
        jsr     PRBYTE
        pla
        ldx     #num_errors-1
@find:  cmp     err_codes,x
        beq     @found
        dex
        bpl     @find
        jmp     CROUT           ; unknown code: number only
@found:
        txa
        pha
        lda     #' ' | $80
        jsr     COUT
        pla
        tax
        lda     err_msg_lo,x
        ldy     err_msg_hi,x
        jsr     print
        jmp     CROUT

; Call GET_FILE_INFO on path. Carry set and A = error code on failure.
get_info:
        lda     #$0A            ; GET_FILE_INFO takes 10 parameters
        sta     info_parms
        jsr     MLI
        .byte   GET_INFO_CMD
        .word   info_parms
        rts

; Print the prompt at A (lo), Y (hi) and read a line into INBUF with
; GETLN, which shows ':' as its own prompt character
input:
        jsr     print
        lda     PROMPT
        pha
        lda     #':' | $80
        sta     PROMPT
        jsr     GETLN
        pla
        sta     PROMPT
        rts

; Ask for the date until a valid one is entered, and put it in DATE and
; TIME on the global page, where ProDOS uses it from then on.
; Returns carry set if the user cancels with an empty line.
ask_date:
        PRINT   msg_no_date
@ask:   lda     #<msg_date
        ldy     #>msg_date
        jsr     input
        ldx     #0
        jsr     skip_spaces
        cmp     #CR
        bne     @parse
        sec                     ; empty line
        rts
@parse: jsr     parse_date
        bcc     @set
        PRINT   msg_bad_date
        jmp     @ask

@set:   lda     month           ; lo = MMMDDDDD
        and     #7
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        ora     day
        sta     DATE
        lda     month           ; hi = YYYYYYYM
        lsr     a
        lsr     a
        lsr     a
        sta     PTR
        lda     year
        asl     a
        ora     PTR
        sta     DATE+1
        lda     minute
        sta     TIME
        lda     hour
        sta     TIME+1
        clc
        rts

; Parse "DD-MON-YY" or "DD-MON-YY HH:MM" from INBUF,X into day, month,
; year, hour and minute. Returns carry set if it is not a valid date.
parse_date:
        lda     #0              ; time defaults to 00:00
        sta     hour
        sta     minute
        jsr     parse_num
        bcs     @bad
        sta     day
        lda     #'-'
        jsr     expect
        bcs     @bad
        jsr     parse_month
        bcs     @bad
        lda     #'-'
        jsr     expect
        bcs     @bad
        jsr     parse_num
        bcs     @bad
        sta     year
        jsr     skip_spaces
        cmp     #CR
        beq     @check

        jsr     parse_num
        bcs     @bad
        cmp     #24
        bcs     @bad
        sta     hour
        lda     #':'
        jsr     expect
        bcs     @bad
        jsr     parse_num
        bcs     @bad
        cmp     #60
        bcs     @bad
        sta     minute
        jsr     skip_spaces
        cmp     #CR
        bne     @bad

@check: lda     day             ; the day must exist in the month
        beq     @bad
        ldy     month
        cmp     days_in_month-1,y
        beq     @ok
        bcc     @ok
        cpy     #2              ; but February has 29 in a leap year
        bne     @bad
        cmp     #29
        bne     @bad
        lda     year
        and     #3
        bne     @bad
@ok:    clc
        rts
@bad:   sec
        rts

; Parse a three letter month name from INBUF,X into month (1-12).
; Returns carry set if it is not one.
parse_month:
        ldy     #0
@read:  lda     INBUF,x
        and     #$7F
        cmp     #'a'
        bcc     @store
        and     #$DF            ; to uppercase
@store: sta     month_buf,y
        inx
        iny
        cpy     #3
        bne     @read

        stx     pos
        ldx     #0              ; offset into month_names
        ldy     #1              ; month number
@try:   lda     month_names,x
        cmp     month_buf
        bne     @next
        lda     month_names+1,x
        cmp     month_buf+1
        bne     @next
        lda     month_names+2,x
        cmp     month_buf+2
        beq     @found
@next:  inx
        inx
        inx
        iny
        cpy     #13
        bne     @try
        ldx     pos
        sec
        rts
@found: sty     month
        ldx     pos
        clc
        rts

; Parse a one or two digit number from INBUF,X. Returns it in A with
; carry clear, or carry set if there is no digit.
parse_num:
        jsr     get_digit
        bcs     @rts
        sta     num
        jsr     get_digit
        bcs     @one
        sta     PTR             ; second digit
        lda     num             ; num * 10 + digit
        asl     a
        asl     a
        adc     num             ; carry is clear: the values are small
        asl     a
        adc     PTR
        sta     num
@one:   lda     num
        clc
@rts:   rts

; If INBUF,X is a digit, return its value in A with carry clear and
; advance X. Otherwise return carry set.
get_digit:
        lda     INBUF,x
        and     #$7F
        sec
        sbc     #'0'
        cmp     #10
        bcs     @rts
        inx
@rts:   rts

; If INBUF,X is the character in A, advance X and return carry clear.
; Otherwise return carry set.
expect:
        sta     PTR
        lda     INBUF,x
        and     #$7F
        cmp     PTR
        bne     @no
        inx
        clc
        rts
@no:    sec
        rts

; Advance X past spaces in INBUF. Returns the next character in A
; without its high bit.
skip_spaces:
        lda     INBUF,x
        and     #$7F
        cmp     #' '
        bne     @done
        inx
        bne     skip_spaces
@done:  rts

; Copy the line GETLN left in INBUF into path as a length-prefixed
; ProDOS pathname. Leading spaces are skipped, the name ends at the
; first space or RETURN, and lowercase is folded to uppercase.
; Returns carry set if the name is too long.
parse_path:
        ldx     #0
        jsr     skip_spaces
        ldy     #0
@copy:  lda     INBUF,x
        and     #$7F
        cmp     #CR
        beq     @done
        cmp     #' '
        beq     @done
        cmp     #'a'
        bcc     @store
        cmp     #'z'+1
        bcs     @store
        and     #$DF            ; to uppercase
@store: cpy     #MAXPATH
        bcs     @long
        sta     path+1,y
        iny
        inx
        bne     @copy
@done:  sty     path
        clc
        rts
@long:  sec
        rts

; Put the pathname to hand to the MLI in fullpath. ProDOS rejects a
; partial pathname when the prefix is empty, which it is after booting,
; but BASIC.SYSTEM accepts one and uses its default slot and drive. Do
; the same by putting the name of the volume in that drive in front.
; Returns carry set and A = error code on failure.
resolve_path:
        lda     path+1
        cmp     #'/'
        beq     @as_is          ; already a full pathname
        jsr     MLI
        .byte   GET_PREFIX_CMD
        .word   prefix_parms
        bcs     @rts
        lda     fullpath
        bne     @as_is          ; the MLI applies the prefix itself

        lda     DEFSLT          ; unit number is DSSS0000
        asl     a
        asl     a
        asl     a
        asl     a
        ldx     DEFDRV
        cpx     #2
        bne     @drive1
        ora     #$80
@drive1:
        sta     online_unit
        jsr     MLI             ; volume name goes to fullpath+1 so the
        .byte   ON_LINE_CMD     ; slashes fit around it
        .word   online_parms
        bcs     @rts
        lda     fullpath+1      ; DSSSLLLL
        and     #$0F
        bne     @have_vol
        lda     fullpath+2      ; no name: this byte is the error code
        sec
        rts
@have_vol:
        tax                     ; build "/VOLUME/" + path
        lda     #'/'
        sta     fullpath+1
        sta     fullpath+2,x
        inx
        inx
        ldy     #0
@append:
        cpy     path
        beq     @done
        cpx     #MAXPATH
        bcs     @long
        lda     path+1,y
        sta     fullpath+1,x
        inx
        iny
        bne     @append
@done:  stx     fullpath
        clc
@rts:   rts
@long:  lda     #ERR_INVALID_PATH
        sec
        rts

@as_is: ldx     path
@copy:  lda     path,x
        sta     fullpath,x
        dex
        bpl     @copy
        clc
        rts

; Print the length-prefixed pathname in path
print_path:
        ldx     #0
@loop:  cpx     path
        beq     @done
        lda     path+1,x
        ora     #$80
        jsr     COUT
        inx
        bne     @loop
@done:  rts

; Print DATE and TIME in the style of CATALOG: DD-MON-YY HH:MM
print_timestamp:
        lda     DATE            ; day
        and     #$1F
        jsr     print_dec2
        lda     #'-' | $80
        jsr     COUT

        lda     DATE+1          ; month is bit 0 of hi and bits 7-5 of lo
        lsr     a
        lda     DATE
        ror     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        tax                     ; month, 1-12
        dex
        cpx     #12
        bcc     @month
        ldx     #12             ; out of range: print "???"
@month: txa                     ; X = (month - 1) * 3
        sta     PTR
        asl     a
        adc     PTR             ; carry is clear after asl of a value < 128
        tax
        ldy     #3
@name:  lda     month_names,x
        ora     #$80
        jsr     COUT
        inx
        dey
        bne     @name
        lda     #'-' | $80
        jsr     COUT

        lda     DATE+1          ; year, 0-99
        lsr     a
        jsr     print_dec2
        lda     #' ' | $80
        jsr     COUT

        lda     TIME+1          ; hour
        jsr     print_dec2
        lda     #':' | $80
        jsr     COUT
        lda     TIME            ; minute
        ; fall through

; Print A (0-99) as two decimal digits
print_dec2:
        ldx     #'0' | $80
@tens:  cmp     #10
        bcc     @ones
        sbc     #10             ; carry is set here
        inx
        bne     @tens
@ones:  pha
        txa
        jsr     COUT
        pla
        ora     #'0' | $80
        jmp     COUT

; Print the zero terminated string at A (lo), Y (hi)
print:
        sta     PTR
        sty     PTR+1
        ldy     #0
@loop:  lda     (PTR),y
        beq     @done
        ora     #$80
        jsr     COUT
        iny
        bne     @loop
@done:  rts

; MLI parameter lists

; Shared by GET_FILE_INFO ($0A parameters) and SET_FILE_INFO (7). The
; layouts match: the storage type and blocks used that GET_FILE_INFO
; returns sit in the slot SET_FILE_INFO ignores.
info_parms:
        .byte   $0A             ; parameter count
        .word   fullpath        ; pathname
        .byte   0               ; access
        .byte   0               ; file type
        .word   0               ; aux type
        .byte   0               ; storage type / unused
        .word   0               ; blocks used / unused
info_mod_date:
        .word   0               ; modification date
        .word   0               ; modification time
        .word   0               ; creation date
        .word   0               ; creation time

create_parms:
        .byte   7               ; parameter count
        .word   fullpath        ; pathname
        .byte   $C3             ; access: destroy, rename, write, read
        .byte   $04             ; file type: TXT
        .word   0               ; aux type (record length)
        .byte   1               ; storage type: seedling file
        .word   0               ; creation date: 0 = now
        .word   0               ; creation time: 0 = now

prefix_parms:
        .byte   1               ; parameter count
        .word   fullpath        ; buffer

online_parms:
        .byte   2               ; parameter count
online_unit:
        .byte   0               ; unit number
        .word   fullpath+1      ; buffer, 16 bytes

; Data

verb:   .word   msg_touched

month_names:
        .byte   "JANFEBMARAPRMAYJUNJULAUGSEPOCTNOVDEC???"

days_in_month:
        .byte   31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31

msg_prompt:     .byte   "FILE TO TOUCH", 0
msg_touched:    .byte   "TOUCHED ", 0
msg_created:    .byte   "CREATED ", 0
msg_too_long:   .byte   "PATHNAME TOO LONG", CR, 0
msg_no_date:    .byte   "NO DATE IS SET. ENTER TODAY'S DATE AS", CR
                .byte   "DD-MON-YY OR DD-MON-YY HH:MM", CR, 0
msg_date:       .byte   "DATE", 0
msg_bad_date:   .byte   "INVALID DATE", CR, 0
msg_error:      .byte   "ERROR $", 0

err_codes:
        .byte   $27, $28, $2B, $40, $44, $45, $46, $48, $49, $4E, $52
num_errors = * - err_codes

.define ERR_MSGS e27, e28, e2B, e40, e44, e45, e46, e48, e49, e4E, e52
err_msg_lo:     .lobytes ERR_MSGS
err_msg_hi:     .hibytes ERR_MSGS

e27:    .byte   "I/O ERROR", 0
e28:    .byte   "NO DEVICE CONNECTED", 0
e2B:    .byte   "WRITE PROTECTED", 0
e40:    .byte   "INVALID PATHNAME", 0
e44:    .byte   "PATH NOT FOUND", 0
e45:    .byte   "VOLUME NOT FOUND", 0
e46:    .byte   "FILE NOT FOUND", 0
e48:    .byte   "DISK FULL", 0
e49:    .byte   "DIRECTORY FULL", 0
e4E:    .byte   "FILE LOCKED", 0
e52:    .byte   "NOT A PRODOS DISK", 0

; The date being entered
day:    .res    1
month:  .res    1
year:   .res    1
hour:   .res    1
minute: .res    1
month_buf:
        .res    3

num:    .res    1               ; parse_num's result
pos:    .res    1               ; saved input position

; Length-prefixed pathnames: as typed, and as given to the MLI
path:   .res    MAXPATH+1
fullpath:
        .res    MAXPATH+1
