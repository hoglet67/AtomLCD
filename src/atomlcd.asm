IRQ1V         = $0204
WRCVEC        = &0208

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

org &A000 - 22

    EQUS "ATOMLCD"
    EQUB 0,0,0,0,0,0,0,0,0
    EQUW &A000
    EQUW &A000
    EQUW &1000

.init
    ;; LINK #A000 to be interrupt driven
    JMP init_via

    ;; LINK #A003 to be vector driven

.init_revector
    LDA #<oswrch
    STA WRCVEC
    LDA #>oswrch
    STA WRCVEC + 1
    JMP reset_display

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
    EQUB &02
    EQUB &06
    EQUB &0F
    EQUB &38
.init_data_end

.via_isr
    LDA ViaT1CounterL       ; Clear the VIA interrupt flag
    JSR update              ; refresh the LCD
    PLA                     ; the Atom OS stacks A
    RTI                     ; return from interrupt

.oswrch
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

FOR n, P%, &AFFF
    EQUB &FF
NEXT

SAVE "ATOMLCD.rom", &A000, &B000

SAVE "ATOMLCD", &9FEA, &B000
