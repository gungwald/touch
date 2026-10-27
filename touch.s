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
;
; Then, if the file has no creation date, touch offers to set one:
;
;     NO CREATION DATE. SET IT TO (N)OW, TO
;     A DATE YOU (E)NTER, OR (I)GNORE IT? N
;     CREATION DATE SET TO 26-OCT-26 14:05
;
; ProDOS 8 has no call that sets a creation date, so touch reads the
; file's directory entry with READ_BLOCK, changes it, and writes it back
; with WRITE_BLOCK.
;

        .setcpu "6502"

; ProDOS MLI and global page
MLI             = $BF00
DEVNUM          = $BF30         ; last device used
DATE            = $BF90         ; date: lo = MMMDDDDD, hi = YYYYYYYM
TIME            = $BF92         ; time: lo = minute, hi = hour

READ_BLOCK_CMD  = $80
WRITE_BLOCK_CMD = $81
GET_TIME_CMD    = $82
CREATE_CMD      = $C0
SET_INFO_CMD    = $C3
GET_INFO_CMD    = $C4
ON_LINE_CMD     = $C5
GET_PREFIX_CMD  = $C7

ERR_INVALID_PATH   = $40
ERR_FILE_NOT_FOUND = $46

; ProDOS directory blocks
ENTRY_LEN       = $27           ; bytes in a directory entry
PER_BLOCK       = $0D           ; entries in a directory block
H_ENTRY_LEN     = $1F           ; header: entry length, then per block
E_KEY           = $11           ; entry: key block
E_CREATE        = $18           ; entry: creation date and time
ST_SUBDIR       = $D0           ; storage type of a subdirectory

; BASIC.SYSTEM global page
DEFSLT          = $BE3C         ; default slot
DEFDRV          = $BE3D         ; default drive

; Monitor
PROMPT          = $33           ; prompt character for get_line
INBUF           = $0200         ; input buffer
RDKEY           = $FD0C
CROUT           = $FD8E
PRBYTE          = $FDDA
COUT            = $FDED

; Zero page
PTR             = $06           ; free for user programs
ENTRY           = $08           ; directory entry in block_buf

MAXPATH         = 64            ; longest ProDOS pathname
MAXLINE         = 239           ; longest line get_line accepts
CR              = $0D

; Keys, as RDKEY returns them, and characters for COUT
KEY_BELL        = $87
KEY_LEFT        = $88           ; left arrow; backspace for COUT
KEY_RETURN      = $8D
KEY_RIGHT       = $95           ; right arrow
KEY_CANCEL      = $98           ; Ctrl-X
KEY_DELETE      = $FF

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
        sta     stamp,x
        dex
        bpl     @copy

        lda     #7              ; SET_FILE_INFO takes 7 parameters
        sta     info_parms
        jsr     MLI
        .byte   SET_INFO_CMD
        .word   info_parms
        bcs     error
        lda     DEVNUM          ; the device the file is on
        sta     rw_unit

        ; Report what was done: "TOUCHED PATH DD-MON-YY HH:MM"
        lda     verb
        ldy     verb+1
        jsr     print
        jsr     print_path
        lda     #' ' | $80
        jsr     COUT
        jsr     print_timestamp
        jsr     CROUT

        lda     info_create_date
        ora     info_create_date+1
        bne     @done
        jmp     fix_create      ; the file has no creation date
@done:  rts

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
; get_line, which shows ':' as its own prompt character
input:
        jsr     print
        lda     PROMPT
        pha
        lda     #':' | $80
        sta     PROMPT
        jsr     get_line
        pla
        sta     PROMPT
        rts

; Read a line like the Monitor's GETLN: print the prompt character in
; PROMPT, read keys into INBUF until RETURN, and return the length in X
; with a RETURN stored after the line.
;
; As in GETLN, the left arrow moves back over the line and the right
; arrow moves forward again, taking back the character it passes. The
; characters to the right of the cursor stay on the screen and are
; dropped if RETURN is pressed. Typing replaces them, and Ctrl-X cancels
; the line. Unlike GETLN, Delete erases the character to the left of
; the cursor and closes up the gap, as on a Mac, and there is no ESC
; editing. Other control characters, including up and down arrows, are
; ignored. Everything is printed through COUT, so it works in 40 or 80
; columns.
get_line:
        lda     PROMPT
        jsr     COUT
        ldx     #0              ; X is the cursor position in the line
        stx     line_len        ; line_len counts the characters to its
@key:   jsr     RDKEY           ; right as well
        cmp     #KEY_RETURN
        beq     @return
        cmp     #KEY_LEFT
        beq     @left
        cmp     #KEY_RIGHT
        beq     @right
        cmp     #KEY_DELETE
        beq     @delete
        cmp     #KEY_CANCEL
        beq     @cancel
        cmp     #' ' | $80
        bcc     @key            ; other control characters
        cpx     #MAXLINE
        bcs     @full
        sta     INBUF,x
        jsr     COUT
        inx
        cpx     line_len
        bcc     @key
        stx     line_len
        bcs     @key            ; always taken
@full:  lda     #KEY_BELL
        jsr     COUT
        jmp     @key

@cancel:
        lda     #'\' | $80
        jsr     COUT
        jsr     CROUT
        jmp     get_line

@return:
        stx     PTR             ; blank out anything right of the cursor
        lda     line_len
        sec
        sbc     PTR
        tay
        beq     @end
        lda     #' ' | $80
@clear: jsr     COUT
        dey
        bne     @clear
@end:   lda     #KEY_RETURN
        sta     INBUF,x
        jmp     COUT

@left:  txa
        beq     @key            ; already at the start
        dex
        lda     #KEY_LEFT
        jsr     COUT
        jmp     @key

@right: cpx     line_len
        bcs     @key            ; already at the end
        lda     INBUF,x
        jsr     COUT
        inx
        jmp     @key

@delete:
        txa
        beq     @key            ; nothing to the left
        dex
        lda     #KEY_LEFT
        jsr     COUT
        stx     PTR             ; where the cursor goes back to
@shift: inx                     ; move the rest of the line left one
        cpx     line_len        ; place, printing it as it goes
        bcs     @blank
        lda     INBUF,x
        sta     INBUF-1,x
        jsr     COUT
        jmp     @shift
@blank: lda     #' ' | $80      ; blank out the old last character
        jsr     COUT
@back:  lda     #KEY_LEFT       ; back to the cursor position
        jsr     COUT
        dex
        cpx     PTR
        bne     @back
        dec     line_len
        jmp     @key

; Ask for the date until a valid one is entered, and put it in DATE and
; TIME on the global page, where ProDOS uses it from then on.
; Returns carry set if the user cancels with an empty line.
ask_date:
        PRINT   msg_no_date
        jsr     read_date
        bcs     @rts
        ldx     #3
@copy:  lda     stamp,x
        sta     DATE,x
        dex
        bpl     @copy
        clc
@rts:   rts

; Show the date format and ask for a date until a valid one is entered.
; Put it in stamp in ProDOS's form: date (lo, hi), minute, hour.
; Returns carry set if the user cancels with an empty line.
read_date:
        PRINT   msg_date_format
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
        sta     stamp
        lda     month           ; hi = YYYYYYYM
        lsr     a
        lsr     a
        lsr     a
        sta     PTR
        lda     year
        asl     a
        ora     PTR
        sta     stamp+1
        lda     minute
        sta     stamp+2
        lda     hour
        sta     stamp+3
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

; Copy the line get_line left in INBUF into path as a length-prefixed
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

; The file has no creation date. Ask whether to set it to now, to a date
; the user enters, or to leave it alone.
fix_create:
        PRINT   msg_no_create
@key:   jsr     RDKEY
        cmp     #'a' | $80
        bcc     @upper
        and     #$DF            ; to uppercase
@upper: cmp     #'N' | $80
        beq     @now
        cmp     #'E' | $80
        beq     @enter
        cmp     #'I' | $80
        beq     @ignore
        lda     #KEY_BELL
        jsr     COUT
        jmp     @key

@ignore:
        jsr     COUT
        jmp     CROUT

@now:   jsr     COUT            ; the date and time the file was touched
        jsr     CROUT           ; with are still in stamp
        jmp     set_create

@enter: jsr     COUT
        jsr     CROUT
        PRINT   msg_enter_create
        jsr     read_date
        bcc     set_create
        rts                     ; empty line: leave it alone

; Write the date and time in stamp into the file's creation date.
; ProDOS 8 has no call that sets a creation date, so this finds the
; file's entry in its directory and writes the directory block back.
set_create:
        jsr     make_abspath
        bcs     @error
        jsr     find_entry
        bcc     @found
        cmp     #0
        beq     @not_found
@error: jmp     error

@found: ldy     #E_CREATE       ; make sure the entry still has no
        lda     (ENTRY),y       ; creation date before changing it
        iny
        ora     (ENTRY),y
        bne     @not_found
        ldy     #E_CREATE
        ldx     #0
@put:   lda     stamp,x
        sta     (ENTRY),y
        iny
        inx
        cpx     #4
        bne     @put
        jsr     MLI
        .byte   WRITE_BLOCK_CMD
        .word   rw_parms
        bcs     @error
        PRINT   msg_create_set
        jsr     print_timestamp
        jmp     CROUT

@not_found:
        PRINT   msg_no_entry
        rts

; Put the full pathname of the file in abspath, adding the prefix in
; front of a partial pathname, and a slash after the last name to mark
; the end. Returns carry set and A = error code on failure.
make_abspath:
        lda     fullpath+1
        cmp     #'/'
        beq     @full
        jsr     MLI             ; abspath = prefix + fullpath
        .byte   GET_PREFIX_CMD
        .word   abs_prefix_parms
        bcs     @rts
        ldx     abspath
        ldy     #0
@add:   cpy     fullpath
        beq     @end
        lda     fullpath+1,y
        sta     abspath+1,x
        inx
        iny
        bne     @add
@end:   stx     abspath
        bcs     @mark           ; carry is set by cpy when equal

@full:  ldx     fullpath
@copy:  lda     fullpath,x
        sta     abspath,x
        dex
        bpl     @copy
        ldx     abspath
@mark:  lda     #'/'
        sta     abspath+1,x
        clc
@rts:   rts

; Find the directory entry for abspath on the unit in rw_unit, reading
; directory blocks with READ_BLOCK from the volume directory down. The
; name in each directory's header must match the path too.
; Returns carry clear with the entry's block in block_buf, its number
; in rw_block, and ENTRY pointing at the entry. Otherwise returns carry
; set and A = the MLI error code, or 0 if the entry was not found.
find_entry:
        lda     #2              ; the volume directory starts at block 2
        sta     rw_block
        lda     #0
        sta     rw_block+1
        lda     #2              ; first name, after the leading slash
        sta     path_pos
        jsr     next_name       ; the volume name
        bcc     @dir
        lda     #0              ; not found
        rts

@dir:   jsr     MLI             ; read the first block of a directory
        .byte   READ_BLOCK_CMD
        .word   rw_parms
        bcs     @rts
        lda     #0
        sta     entry_idx
        jsr     point_entry     ; its header
        ldy     #H_ENTRY_LEN    ; only standard directories
        lda     (ENTRY),y
        cmp     #ENTRY_LEN
        bne     @not_found
        iny
        lda     (ENTRY),y
        cmp     #PER_BLOCK
        bne     @not_found
        jsr     match_name      ; the header names the same directory
        bne     @not_found
        jsr     next_name       ; the name to look for in it
        bcs     @not_found

        inc     entry_idx       ; skip the header
@entry: lda     entry_idx
        cmp     #PER_BLOCK
        bcs     @next_block
        jsr     point_entry
        jsr     match_name
        beq     @found
        inc     entry_idx
        bne     @entry

@next_block:
        lda     block_buf+2     ; follow the link to the next block
        sta     rw_block
        lda     block_buf+3
        sta     rw_block+1
        ora     rw_block
        beq     @not_found      ; that was the last one
        jsr     MLI
        .byte   READ_BLOCK_CMD
        .word   rw_parms
        bcs     @rts
        lda     #0
        sta     entry_idx
        beq     @entry          ; always taken

@found: lda     abspath
        cmp     path_pos
        bcc     @done           ; the last name: this is the file
        ldy     #0              ; otherwise it is a directory to go into
        lda     (ENTRY),y
        and     #$F0
        cmp     #ST_SUBDIR
        bne     @not_found
        ldy     #E_KEY
        lda     (ENTRY),y
        sta     rw_block
        iny
        lda     (ENTRY),y
        sta     rw_block+1
        jmp     @dir

@done:  clc
        rts
@not_found:
        lda     #0
        sec
@rts:   rts

; Set name_start and name_len to the next name in abspath, starting at
; path_pos, and move path_pos past it and the slash after it.
; Returns carry set if there are no more names.
next_name:
        ldx     path_pos
        lda     abspath
        cmp     path_pos
        bcc     @none           ; past the end
        stx     name_start
@scan:  lda     abspath,x
        cmp     #'/'
        beq     @end
        inx
        bne     @scan
@end:   txa
        sec
        sbc     name_start
        sta     name_len
        inx
        stx     path_pos
        clc
        rts
@none:  sec
        rts

; Compare the name in the directory entry at ENTRY with the name at
; name_start in abspath. Returns Z set if they match. Deleted entries
; never match.
match_name:
        ldy     #0
        lda     (ENTRY),y
        cmp     #$10
        bcc     @no             ; storage type 0: deleted
        and     #$0F            ; name length
        cmp     name_len
        bne     @no
        tax
        beq     @no
        stx     name_left
        ldx     name_start
        ldy     #1
@cmp:   lda     abspath,x
        cmp     (ENTRY),y
        bne     @no
        inx
        iny
        dec     name_left
        bne     @cmp
        rts                     ; Z is set
@no:    lda     #1              ; Z clear
        rts

; Point ENTRY at entry number entry_idx in block_buf
point_entry:
        lda     #<(block_buf+4)
        sta     ENTRY
        lda     #>(block_buf+4)
        sta     ENTRY+1
        ldx     entry_idx
        beq     @rts
@add:   clc
        lda     ENTRY
        adc     #ENTRY_LEN
        sta     ENTRY
        bcc     @next
        inc     ENTRY+1
@next:  dex
        bne     @add
@rts:   rts

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

; Print the date and time in stamp in the style of CATALOG:
; DD-MON-YY HH:MM
print_timestamp:
        lda     stamp           ; day
        and     #$1F
        jsr     print_dec2
        lda     #'-' | $80
        jsr     COUT

        lda     stamp+1         ; month is bit 0 of hi and bits 7-5 of lo
        lsr     a
        lda     stamp
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

        lda     stamp+1         ; year, 0-99
        lsr     a
        jsr     print_dec2
        lda     #' ' | $80
        jsr     COUT

        lda     stamp+3         ; hour
        jsr     print_dec2
        lda     #':' | $80
        jsr     COUT
        lda     stamp+2         ; minute
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
info_create_date:
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

abs_prefix_parms:
        .byte   1               ; parameter count
        .word   abspath         ; buffer

rw_parms:                       ; READ_BLOCK and WRITE_BLOCK
        .byte   3               ; parameter count
rw_unit:
        .byte   0               ; unit number
        .word   block_buf       ; buffer
rw_block:
        .word   0               ; block number

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
msg_no_date:    .byte   "NO DATE IS SET. ENTER TODAY'S DATE AS", CR, 0
msg_enter_create:
                .byte   "ENTER THE CREATION DATE AS", CR, 0
msg_date_format:
                .byte   "DD-MON-YY OR DD-MON-YY HH:MM", CR, 0
msg_no_create:  .byte   "NO CREATION DATE. SET IT TO (N)OW, TO", CR
                .byte   "A DATE YOU (E)NTER, OR (I)GNORE IT? ", 0
msg_create_set: .byte   "CREATION DATE SET TO ", 0
msg_no_entry:   .byte   "CAN'T FIND THE DIRECTORY ENTRY", CR, 0
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

; Variables. They are set before they are used, so they take no room in
; the file.
        .segment "BSS"

; A date and time in ProDOS's form: date (lo, hi), minute, hour
stamp:  .res    4

; The date being entered
day:    .res    1
month:  .res    1
year:   .res    1
hour:   .res    1
minute: .res    1
month_buf:
        .res    3

num:    .res    1               ; parse_num's result
line_len:
        .res    1               ; get_line's line length
pos:    .res    1               ; saved input position

; Length-prefixed pathnames: as typed, and as given to the MLI
path:   .res    MAXPATH+1
fullpath:
        .res    MAXPATH+1

; Finding a directory entry
abspath:                        ; full pathname: prefix + partial path,
        .res    2*MAXPATH+2     ; and a slash after the end
path_pos:
        .res    1               ; where the next name starts in abspath
name_start:
        .res    1               ; the current name in abspath
name_len:
        .res    1
name_left:
        .res    1               ; characters left to compare
entry_idx:
        .res    1               ; entry number in block_buf
block_buf:
        .res    512
