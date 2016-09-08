ORIGIN        = $A000
LEN           = $1000
        
IRQ1V         = $0204
WRCVEC        = &0208
RDCVEC        = &020A

WRCH          = &FE52


LCD_CTRL      = &B404
LCD_DATA      = &B405

VSYNC         = &FE66

TMP           = &9E

;;; VIA Addresses
ViaBase       = $B800
ViaT1CounterL = ViaBase + 4
ViaT1CounterH = ViaBase + 5
ViaACR        = ViaBase + 11
ViaIER        = ViaBase + 14

org ORIGIN - 22

    EQUS "ATOMLCD"
    EQUB 0,0,0,0,0,0,0,0,0
    EQUW ORIGIN
    EQUW ORIGIN
    EQUW LEN

.init
    ;; LINK #A000 to be interrupt driven
    JMP init_via

    ;; LINK #A003 to be vector driven

.init_revector
    LDA #<oswrch
    STA WRCVEC
    LDA #>oswrch
    STA WRCVEC + 1
    LDA #<osrdch
    STA RDCVEC
    LDA #>osrdch
    STA RDCVEC + 1
    JSR reset_display
    JMP update
        
.init_via
    LDA #<via_isr           ; Setup the interrupt handler
    STA IRQ1V
    LDA #>via_isr
    STA IRQ1V+1
    LDA #<9999              ; 10ms timer interrupts
    STA ViaT1CounterL
    LDA #>9999
    STA ViaT1CounterH
    LDA #$40                ; Enable T1 continuous interrupts
    STA ViaACR              ; Disable everything else
    LDA #$7F                ; Disable all interrupts
    STA ViaIER
    LDA #$C0                ; Enable T1 interrupts
    STA ViaIER

.reset_display
    LDX #(init_data_end - init_data - 1)
.reset_loop
    LDA init_data,X
    STA LCD_CTRL
    JSR VSYNC
    DEX
    BPL reset_loop

    RTS

.init_data
    EQUB &01
    EQUB &06
    EQUB &0F
    EQUB &38
.init_data_end

.via_isr
    LDA ViaT1CounterL       ; Clear the VIA interrupt flag
    JSR update              ; refresh the LCD
    PLA                     ; the Atom OS stacks A
    RTI                     ; return from interrupt



.osrdch

    PHP                   ;    Save flags
    CLD                   ;
    STX &E4               ;    Save X register
    STY &E5               ;    Save Y register
                          ;
                          ;                WAIT FOR KEYBOARD TO BE RELEASED
                          ;
.LFE9A                    ;
    BIT &B002             ;    Is <REPT> key pressed ?
    BVC LFEA4             ;    ..yes, no need to wait for keyboard to
                          ;     be released
    JSR &FE71             ;    Scan keyboard
    BCC LFE9A             ;    ..wait for key to be released
                          ;
                          ;                GET KEYPRESS
                          ;
.LFEA4                    ;
    JSR &FB8A             ;    Wait 0.1 second for debounce
.LFEA7                    ;
    JSR &FE71             ;    Scan keyboard
    BCS LFEA7             ;    ..keep scanning until key pressed
    JSR &FE71             ;    Scan keyboard again - still pressed ?
    BCS LFEA7             ;    ..no, noise ? - try again
    TYA                   ;    Acc = ASCII value of key - &20
    LDX #&17              ;    Pointer to control code table at &FEE2
                          ;
                          ;               GET EXECUTION ADDRESS AND JUMP TO IT
                          ;
    JSR &FEC5             ;    Test for control code or otherwise
    LDA LFEE3,X           ;    Get LSB execution Aaddress
    STA &E2               ;    ..into w/s
    LDA handler_hi_byte,X ;    Get MSB execution Address
    STA &E3               ;    ..into w/s
    TYA                   ;    Acc = ASCII value of key - &20
    JMP (&E2)             ;    Jump to deal with char or control code

;;  Handle Cursor Keys from Keyboard subroutine
;;  -------------------------------------------

;;- Sends the cursor control code to screen and then fetches another key.

.LFDA2
    AND #&5
    ROL &B001
    ROL A
    JSR &FCEA              ; Send control character to screen
    JSR update
    JMP LFE9A              ; ..and fetch another key
        
.LFEE3

    ;; oswrch handlers (unused)
    EQUB &44, &5C, &38, &62, &87, &69, &40, &8D, &92, &7D, &50

    ;; osrdch handlers (used!)
    EQUB &DF, &D2, &9A, <LFDA2, &E2, &AE, &C0, &DF, &D8, &D6, &C8, &C6, &C2

.handler_hi_byte
    ;; oswrch handlers (unused)
    EQUB &00, &00, &00, &00, &00, &00, &00, &00, &00, &00, &00

    ;; osrdch handlers (used!)
    EQUB &FD, &FD, &FD, >LFDA2, &FD, &FD, &FD, &FD, &FD, &FD, &FD, &FD, &FD

        
.oswrch

    PHA
        
    ;; optimise the common case of a non control character
    CMP #&7F
    BEQ slowpath
    CMP #&20
    BCC slowpath

    ;; also bail if we are right at the end of the line
    LDA &E0
    CMP #&1F
    BCS slowpath

    ;; just update one character on the display
    PLA
        
    PHA
    STA LCD_DATA
    JSR delay40
    PLA

    ;; finish by writing to the atom display
    JMP WRCH
        
.slowpath
    PLA
        
    ;; call the old OSWRCH first
    JSR WRCH

    ;; update the LCD
.update

    ;; save everything
    PHP
    PHA
    TXA
    PHA
    TYA
    PHA

    ;; assume the cursor is on the second line
    LDY #64

    ;; calculate start address of previous line
    SEC
    LDA &DE
    SBC #32
    STA TMP
    LDA &DF
    SBC #00
    STA TMP+1

    ;; check whether we have gone off the top of the screen
    BMI not_at_top
    LDY #&80
    STY TMP + 1
    LDY #&00
    STY TMP
.not_at_top

    ;; Pre-calculate command to set cursor position on LCD
    TYA
    CLC
    ADC &E0
    ORA #&80
    PHA

    ;; X is the LCD line counter
    LDX #0
    ;; Y is the Atom character pointer
    LDY #0

.display_loop_1

    ;; set the display DRAM address to start of line X (X * 64)
    TXA
    CLC
    ROR A
    ROR A
    SEC
    ROR A
    STA LCD_CTRL
    JSR delay40

.display_loop_2
    LDA (TMP),Y

    ;; convert to ascii
    JSR toascii

    ;; output ascii character to display
    STA LCD_DATA
    JSR delay40

    ;; continue to the end of the line
    INY
    TYA
    AND #&1F
    BNE display_loop_2

    ;; move on to the next line
    INX
    CPX #2
    BNE display_loop_1

    ;; move the cursor to the correct position
    PLA
    PHA
    STA LCD_CTRL
    JSR delay40

    ;; redraw the character under the cursor, xor'ed with the cursor, so it's not inverted
    LDY &E0
    LDA (&DE),Y
    EOR &E1
    JSR toascii
    STA LCD_DATA
    JSR delay40

    ;; move the cursor to the correct position
    PLA
    STA LCD_CTRL
    JSR delay40

    PLA
    TAY
    PLA
    TAX
    PLA
    PLP
    RTS

.toascii
    ;; test bit6 = 0 for an ascii character
    PHA
    ASL A
    ASL A
    PLA
    BCC ascii0

    ;; substitute a square block for a graphic character
    LDA #&FF
    BCS ascii3

    ;; convert 6847 character to ASCII
    ;; 00-1F -> 40-5F
    ;; 20-3F -> 20-3F
    ;; 80-9F -> 60-7F
    ;; A0-BF -> 20-3F
.ascii0
    CMP #&20
    BCC ascii1
    CMP #&80
    BCC ascii2
    CMP #&A0
    BCS ascii2
    EOR #&20
.ascii1
    EOR #&40
.ascii2
    AND #&7F
.ascii3
    RTS

.delay40           ;; 6 (JSR)
    PHA            ;; 3
    LDA #&03       ;; 2
.delay_loop
    SEC            ;; 2
    SBC #&01       ;; 2
    BNE delay_loop ;; 3
    PLA            ;; 4
    RTS            ;; 6
                   ;; total is 42

FOR n, P%, ORIGIN + LEN - 1
    EQUB &FF
NEXT

SAVE "ATOMLCD.rom", ORIGIN, ORIGIN + LEN

SAVE "ATOMLCD", ORIGIN - 22, ORIGIN + LEN
