;-------------------------------------------------------------------------
;  65c02 Breadboard project - µBoot bootloader
;-------------------------------------------------------------------------

;-------------------------------------------------------------------------
;  Physical mappings
;  $0 - $FF Zero Page
;  $0100-$01FF Stack
;  $0200-$3FFF RAM
;  $5000 	   Serial port
;  $6000-$600F VIA #1
;  $8000-$FFFF ROM
;-------------------------------------------------------------------------

V_RTC_SEC 		= $0 					; RTC time variables
V_RTC_MIN 		= $1
V_RTC_HR 		= $2

V_P_STR_LO  	= $3 					; String address pointer, used for printing
V_P_STR_HI  	= $4 					; String address pointer, used for printing
S_DATA_RDY 		= $5 					; Data available from serial bus, used by NMI
S_IN_BYTE 		= $6					; Input byte from serial bus, used by NMI
S_BYTE_COUNT	= $7 					; Incoming byte counter, used by serial test app

V_DISP_CHANGED 	= $8 					; Has bootloader menu state changed (need to redraw)
V_JUMP_REQ 		= $9 					; Is there a jump request from user
V_KEYSTROKE 	= $10 					; User keystroke variable
V_LCD_SELECTION = $11					; Current menu item
V_JMP_SELECTION = $12 					; Selected item
V_IN_SUBMENU 	= $13 					; Are we in main menu (or builtin app menu)
V_MAX_ENTRIES 	= $14 					; Number of entries in current submenu

CURR_BLOCK		= $15 					; Current payload # being received over serial
CURR_ADDR_L 	= $16 					; Address to write payload byte to
CURR_ADDR_H 	= $17 					; Address to write payload byte to
CHECKSUM 		= $18 					; Checksum, calculated per 128-byte payload

USR_PROG 		= $0200 				; Start of user program storage in RAM
	
ACIA_DATA		= $5000
ACIA_STATUS 	= $5001
ACIA_CMD 		= $5002
PORTB 			= $6000
PORTA 			= $6001
DDRB 			= $6002
DDRA 			= $6003
T2CL 			= $6008
T2CH 			= $6009
SR 				= $600A
ACR 			= $600B
PCR 			= $600C
IFR 			= $600D
IER 			= $600E


;-------------------------------------------------------------------------
;  Constants
;-------------------------------------------------------------------------

LCD_NUM_MASK 	= %00110000 			; Decimal digit to ascii offset

LCD_E  			= %10000000 			; In PORTA
LCD_RW 			= %01000000	
LCD_RS 			= %00100000	
LCD_BUSY    	= %00001000	
	
KEYS_MASK 		= %00011100	
KEY_ENTER 		= %00000100 			; In PORTA
KEY_UP 			= %00001000		
KEY_DN 			= %00010000			
		
SR_IDLE 		= %00000011 			; In PORTA, no conversion triggered, SR in parallel listen mode
SR_CONVERT  	= %00000001		
SR_LATCH 		= %00000010
PORTA_IDLE 		= SR_IDLE		
		
GP0 			= %01000000 			; Spare I/O of PORTA..
GP1				= %00100000		
GP2				= %00010000		
			
DDRA_BITS 		= %11100011		
DDRB_BITS 		= %00001111		
		
LCD_CLR_BITS 	= %00000001 			; LCD clear command
		
MMENU_ENTRIES  	= 3 					; Number of entries in bootloader menu (0-indexed)
BMENU_ENTRIES  	= 2						; Number of entries in the builtin app menu (0-indexed)

SOH 			= 1 					; Start of heading
ENQ 			= 5						; Enquiry
ACK 			= 6 					; Acknowledge
NAK				= 21 					; Negative acknowledge
EOT 			= 26 					; End of transfer


;-------------------------------------------------------------------------
;  Set assembler location counter to match current memory mapping
;-------------------------------------------------------------------------

				.org $8000 				; Location counter $8000, start of ROM


;-------------------------------------------------------------------------
;  Reset vector
;-------------------------------------------------------------------------

RESET:			SEI 					; Disable interrupts for the duration of reset sequence
				JSR DELAY 				; Delay execution to allow peripherals to settle

  				; Initialize VIA	
  				LDA #DDRA_BITS			; Top 3 and lowest pin on A to output
  				STA DDRA
  				LDA #PORTA_IDLE	
  				STA PORTA	
					
  				LDA #DDRB_BITS			; Low 4 pins on port B to output
  				STA DDRB	
  				STZ PORTB	
					
  				LDA #%00101000			; Disable T1, count down T2 with PB6 pulses, SR = input under PHI2, disable latching
  				STA ACR	
  				LDA #%10100000 			; Set VIA interrupt #5 = T2 ISR
  				STA IER

  				LDX #1 					; Flush timer
  				JSR DELAY_X
					
  				; Initialize LCD	
  				JSR INIT_LCD 			; Puts LCD into 4-bit mode and clears it
				JSR DRAW_TITLE 			; Show program title upon launch on LCD
				
				; Initialize bootloader variables
				JSR INIT_VARS 			; Initialize all variables to zero
				INC V_DISP_CHANGED 		; Pre-set display change request to trigger LCD update in bootloader main code

  				; Initialize RTC - VIA T2 to give 1s interrupts:
  				STZ V_RTC_SEC				; Zero RTC count
  				STZ V_RTC_MIN
  				STZ V_RTC_HR
				
  				LDA #15 				; Init T2 low byte with 15 to get 1s interrupts - RTC runs at 8Hz
  				STA T2CL	
  				STZ T2CH				; No need for high byte, but write it to reset VIA ISR bit
  				CLI 					; Enable interrupts TODO maybe move this to prep system for jump function? Or initializer for temp app?


;-------------------------------------------------------------------------
;  Main bootloader structure
;-------------------------------------------------------------------------

BOOT:			LDA V_DISP_CHANGED 		; Do we need to update display?
				BEQ .b0 				; If zero = no, skip ahead
 				JSR UPDATE_LCD	
	
.b0:			JSR GET_USR_INPUT	
				LDA V_JUMP_REQ 			; Did we receive a jump request?
				BEQ .b1 				; If zero = no target, continue running bootloader
	
				JSR PREPARE_JUMP 		; If yes, resolve target and prepare system...
				LDA V_JMP_SELECTION
				ASL
				TAX
 				JMP (TBL_JUMP, X)		; And go!

.b1:			JMP BOOT


;-------------------------------------------------------------------------
;  IRQ vector, runs on hardware interrupt (VIA)
;-------------------------------------------------------------------------

IRQ: 			PHA
  				INC V_RTC_SEC			; Increment seconds in RTC count
  				LDA V_RTC_SEC	
  				CMP #60	
  				BCC .irq0 				; Branch if seconds value under 60
  				SBC #60	
  				STA V_RTC_SEC	
  				INC V_RTC_MIN			; Increment minutes in RTC count
  				LDA V_RTC_MIN				
  				CMP #60	
  				BCC .irq0				; Branch if minutes value under 60
  				SBC #60
  				STA V_RTC_MIN
  				INC V_RTC_HR

.irq0:			LDA #15 				; T2 low byte = 15 to get 1s interrupts
  				STA T2CL	
  				STZ T2CH				; No need for high byte, but write it to reset VIA ISR bit
  				PLA
  				RTI


;-------------------------------------------------------------------------
;  NMI vector, runs on hardware non-maskable interrupt (Teensy subsystem)
;-------------------------------------------------------------------------

NMI: 			LDA ACIA_DATA 			; Teensy interrupts when serial data is available
				STA S_IN_BYTE
				INC S_DATA_RDY
				RTI


;-------------------------------------------------------------------------
;  Subroutine to clear memory for bootloader (TODO extend to entire stack/RAM)
;-------------------------------------------------------------------------

INIT_VARS: 		STZ V_DISP_CHANGED 
				STZ V_P_STR_LO 
				STZ V_P_STR_HI 
				STZ V_JUMP_REQ
				STZ V_KEYSTROKE
				STZ V_LCD_SELECTION
				STZ V_IN_SUBMENU
				STZ V_MAX_ENTRIES
				RTS


;-------------------------------------------------------------------------
;  Application to load a program to RAM
;-------------------------------------------------------------------------

APP_LOAD: 		JSR READ_PROG
				JMP BOOT


;-------------------------------------------------------------------------
;  Application to run a program in RAM
;-------------------------------------------------------------------------

APP_RUN: 		JMP USR_PROG


;-------------------------------------------------------------------------
;  Application to load, then run a program in RAM
;-------------------------------------------------------------------------

APP_LOAD_RUN: 	JSR READ_PROG
				JSR LCD_CLEAR	
				JMP USR_PROG


;-------------------------------------------------------------------------
;  Subroutine to download a program to RAM ($0200->) via serial interface.
;
;  Flow, variation of XMODEM by Ward Christensen:
;  1. Ready to receive, expecting PC to send ENQ (005)
;  2. Send NAK (021) to PC, acknowledge start of transfer
;  3. Receive data. Syntax: SOH (001), Block#, 128-byte payload, chksum
;  4. Calculate checksum, send ACK (006) if ok, send NAK (021) if not ok
;  5. Receive more data, until instead of package starting with SOH (001), we get EOT (026)
;-------------------------------------------------------------------------

READ_PROG: 		LDA #1			 		; Init transfer variables
				STA CURR_BLOCK
				LDA #>USR_PROG
				STA CURR_ADDR_H
				LDA #<USR_PROG
				STA CURR_ADDR_L

				LDA #>str_jmodem		; Show jmodem app title
  				STA V_P_STR_HI
  				LDA #<str_jmodem
  				STA V_P_STR_LO
  				JSR LCD_P_STR

				LDA #40
  				JSR LCD_SET_POS  				

				LDA #>str_ready_to_load	; Show ready title on LCD
  				STA V_P_STR_HI
  				LDA #<str_ready_to_load
  				STA V_P_STR_LO
  				JSR LCD_P_STR

.rp_start		JSR SER_GET_CHR
				CMP #ENQ
				BNE .rp_start 			; Not acceptable start of transfer, check again

				JSR LCD_CLEAR 
				LDA #>str_loading		; Show loading title on LCD
  				STA V_P_STR_HI
  				LDA #<str_loading
  				STA V_P_STR_LO
  				JSR LCD_P_STR
  				LDA #40
  				JSR LCD_SET_POS
  				LDA #>str_block_num		; Show block number text LCD
  				STA V_P_STR_HI
  				LDA #<str_block_num
  				STA V_P_STR_LO
  				JSR LCD_P_STR

  				LDA #NAK 				; Send NAK to start transmission of first block
  				STA ACIA_DATA

.rp_blockstart	JSR SER_GET_CHR			; Start of block
				CMP #EOT
				BEQ .rpdone
				CMP #SOH
				PHP
				LDX #1					; Error 1, block not started with EOT or SOH
				PLP
				BNE .rpfail

				LDY #3
				JSR LCD_MOVEY_L
  				LDA CURR_BLOCK
  				JSR LCD_P_INT3

				; Check block number next
				JSR SER_GET_CHR
				CMP CURR_BLOCK			; Is current block number correct?
				PHP
				LDX #2					; Error 2, block number mismatch
				PLP
				BNE .rpfail

				; Receive payload
				STZ CHECKSUM 			; Reset checksum
				LDX #127
.rp_rcv			JSR SER_GET_CHR
				STA (CURR_ADDR_L)		; Store received byte
				INC CURR_ADDR_L
				BNE .rp0 				; If rolled over to zero, increment high byte
				INC CURR_ADDR_H
.rp0 			CLC 					; Clear carry, add current byte to checksum and store it					
				ADC CHECKSUM
				STA CHECKSUM
				DEX
				BPL .rp_rcv 			; Receive new input byte if payload is not complete

				; Receive checksum, send ACK and increase block count if ok, send NAK if not ok
				JSR SER_GET_CHR 
				CMP CHECKSUM
				BNE .rp1 				; Branch if checksum mismatch
				INC CURR_BLOCK 			; Checksum match, so increase block count
				LDA #ACK 				; Send ACK to acknowledge that checksum is ok
				BRA .rp2
.rp1			LDA #NAK 				; Branching here on checksum mismatch, send NAK to indicate checksum fail
.rp2			STA ACIA_DATA
				JMP .rp_blockstart		; Get new block of data

.rpdone 		JSR LCD_CLEAR
				LDA #>str_success		; Show success message on LCD
  				STA V_P_STR_HI
  				LDA #<str_success
  				STA V_P_STR_LO
  				JSR LCD_P_STR
  				
  				LDA #40					; Go to the second LCD row
  				JSR LCD_SET_POS 

				LDA #>str_rcvd			; Show received block count on LCD
  				STA V_P_STR_HI
  				LDA #<str_rcvd
  				STA V_P_STR_LO
  				JSR LCD_P_STR

  				LDA CURR_BLOCK
  				DEC 					; Handle off by one
  				JSR LCD_P_INT3
  				
  				LDA #>str_blocks	
  				STA V_P_STR_HI
  				LDA #<str_blocks
  				STA V_P_STR_LO
  				JSR LCD_P_STR
  				LDX #30 				; 2 second delay
  				JSR DELAY_X
				RTS 				

.rpfail 		JSR LCD_CLEAR			; Jumped here on transfer error, err # in X
				LDA #>str_tfer_fail		; Show transfer failed msg on LCD
  				STA V_P_STR_HI
  				LDA #<str_tfer_fail
  				STA V_P_STR_LO
  				JSR LCD_P_STR
  				
  				TXA
  				ORA #LCD_NUM_MASK
  				JSR LCD_PRINT
  				
  				LDX #30 				; 2 second delay
  				JSR DELAY_X
				RTS


;-------------------------------------------------------------------------
;  Subroutine to prepare system for jumping
;-------------------------------------------------------------------------

PREPARE_JUMP: 	LDA V_LCD_SELECTION 	; Copy LCD selection to jump table target var
				STA V_JMP_SELECTION 	
				STZ V_LCD_SELECTION

				LDA V_IN_SUBMENU 		; If we are in submenu, need to offset jump target
				BEQ .pj0				; Skip if in main menu
				LDA V_JMP_SELECTION 	; In builtin app submenu, so offset jump
				SEC 					; Handle jump table off by one with carry bit
				ADC #MMENU_ENTRIES
				STA V_JMP_SELECTION

.pj0			INC V_DISP_CHANGED  	; Prepare bootloader if we ever come back..
 				STZ V_JUMP_REQ
 				LDA #LCD_CLR_BITS		; Clear display
  				JSR LCD_CMD_4B	
  				JSR WAIT_LCD 			; LCD is busy after op, wait..
				RTS


;-------------------------------------------------------------------------
;  Jump handlers for menu operations
;-------------------------------------------------------------------------

GOTO_MMENU: 	STZ V_IN_SUBMENU
				JMP BOOT
GOTO_BMENU: 	INC V_IN_SUBMENU
				JMP BOOT


;-------------------------------------------------------------------------
;  Subroutine to delay execution for X * 0.062 (1s/16) seconds
;-------------------------------------------------------------------------

DELAY_X: 		STX T2CL	
  				STZ T2CH
  				WAI
  				RTS


;-------------------------------------------------------------------------
;  Subroutine to get user key input for bootloader navigation
;-------------------------------------------------------------------------

GET_USR_INPUT:  LDA PORTA 				; Read inputs and mask out non-key bits
				AND #KEYS_MASK 	
				BEQ .gui4 				; No keys, skip to RTS
				STA V_KEYSTROKE			; Key found
				LDX #2 					; Debounce delay 120 ms
				JSR DELAY_X	
				LDA PORTA	
				AND #KEYS_MASK 	
				EOR V_KEYSTROKE	
				BNE .gui4 				; If key changed during debounce interval, disregard and RTS
	
				LDX #2 					; Key input accepted. Additional delay to help user keep up with display updates. Flag disp changed.
				JSR DELAY_X	
				INC V_DISP_CHANGED
	
				LDA V_KEYSTROKE 		; Key not changed, so process key
				AND #KEY_ENTER	
				BEQ .gui0 				; Not enter key
				INC V_JUMP_REQ 			; Is enter key, flag jump request and quit
				RTS	

				; Resolve maximum amount of allowed menu entries in current menu
.gui0			LDA V_IN_SUBMENU
				BNE .gui00
				LDA #MMENU_ENTRIES 		; In main menu
				JMP .gui01
.gui00			LDA #BMENU_ENTRIES 		; In submenu				
.gui01			STA V_MAX_ENTRIES

				; Got some up or down key
				LDA V_KEYSTROKE 		; Get key to process
				AND #KEY_DN	
				BEQ .gui1 				; Not dn key
				INC V_LCD_SELECTION	
				JMP .gui2 				; Jump to sanitize menu pos
	
.gui1 			LDA V_KEYSTROKE 		; Key not changed, process key
				AND #KEY_UP	
				BEQ .gui4 				; Not up key
				DEC V_LCD_SELECTION	
	
.gui2 			BMI .gui3 				; Handle illegal menu positions.. Overflow happened via negative -> branch
				LDA V_MAX_ENTRIES	
 				CMP V_LCD_SELECTION	
 				BPL	.gui4				; N flag set if menupos > max entry, branch if N = 0 (legal)
				STZ V_LCD_SELECTION 	; Overflow happened via positive, (max entry + 1), set to 0
				RTS	
	
.gui3			LDA V_MAX_ENTRIES  		; Overflowing though negative, set to max entry
				STA V_LCD_SELECTION 

.gui4			RTS


;-------------------------------------------------------------------------
;  Subroutine to update bootloader screen
;-------------------------------------------------------------------------

UPDATE_LCD: 	LDA #%00000001			; Clear display
  				JSR LCD_CMD_4B	
  				JSR WAIT_LCD 			; LCD is busy after op

				LDA #'>'
  				JSR LCD_PRINT

				LDA V_LCD_SELECTION
				ASL
				TAX
				LDA V_IN_SUBMENU
				BNE .ulcd0

 				LDA TBL_MMENU_ITEMS, X
 				STA V_P_STR_LO
 				INX
 				LDA TBL_MMENU_ITEMS, X
 				STA V_P_STR_HI
 				JMP .ulcd1

.ulcd0 			LDA TBL_BMENU_ITEMS, X
 				STA V_P_STR_LO
 				INX
 				LDA TBL_BMENU_ITEMS, X
 				STA V_P_STR_HI

.ulcd1 			JSR LCD_P_STR 
  				STZ V_DISP_CHANGED
				RTS


;-------------------------------------------------------------------------
;  Subroutine to print bootloader title and credits
;-------------------------------------------------------------------------

DRAW_TITLE:		LDA #>str_uboot_title1	
  				STA V_P_STR_HI	
  				LDA #<str_uboot_title1
  				STA V_P_STR_LO
  				JSR LCD_P_STR	

  				LDA #40 				; Go to the second LCD row
  				JSR LCD_SET_POS
  				LDA #>str_uboot_title2	
  				STA V_P_STR_HI	
  				LDA #<str_uboot_title2
  				STA V_P_STR_LO
  				JSR LCD_P_STR	
					
  				LDX #15 				; T2CL 15 = 1s delay
  				JSR DELAY_X
  				JSR LCD_CLEAR

  				LDA #>str_credits1	
  				STA V_P_STR_HI
  				LDA #<str_credits1
  				STA V_P_STR_LO
  				JSR LCD_P_STR

  				LDA #40					; Go to the second LCD row
  				JSR LCD_SET_POS 
  				LDA #>str_credits2	
  				STA V_P_STR_HI
  				LDA #<str_credits2
  				STA V_P_STR_LO
  				JSR LCD_P_STR
					
  				LDX #15 				; T2CL 15 = 1s delay
  				JSR DELAY_X
  				RTS


;-------------------------------------------------------------------------
;  Subroutine to print a string to LCD, addressed indirectly, pointer at $10, $11
;  Leaves Y loaded with length of printed string
;-------------------------------------------------------------------------

LCD_P_STR:		LDY #0 					; Use Y to index through chars
.lpstr0: 		LDA (V_P_STR_LO),Y 		; Print individual char
  				CMP #255
  				BEQ .lpstr1 			; Print finished if terminating char 255 found
  				JSR LCD_PRINT
  				INY
  				JMP .lpstr0 			
.lpstr1:		INY 					; Y += 1 to match printed char count
				RTS


;-------------------------------------------------------------------------
;  Subroutine to get char from serial interface, TODO Timeout
;  Stores input char in A
;-------------------------------------------------------------------------

SER_GET_CHR: 	LDA ACIA_STATUS 		; Is new data available?
				AND #%00001000
				BEQ SER_GET_CHR 		; If no, check again
				LDA ACIA_DATA 			; If yes, load input byte
				RTS


;-------------------------------------------------------------------------
;  Subroutine to print a string to Serial port, addressed indirectly, pointer at $10, $11
;  Leaves Y loaded with length of printed string
;-------------------------------------------------------------------------

SER_P_STR:		LDY #0 					; Use Y to index through chars
.spstr0: 		LDA (V_P_STR_LO),Y 		; Print individual char
  				CMP #255
  				BEQ .spstr1 			; Print finished if terminating char 255 found
  				STA ACIA_DATA
  				INY
  				JMP .spstr0 			
.spstr1:		INY 					; Y += 1 to match printed char count
				RTS


;-------------------------------------------------------------------------
;  Subroutine to print a 3-digit integer to Serial
;-------------------------------------------------------------------------

SER_P_INT3:		LDX #0 					; 2nd (10ths) digit in accumulator X
  				LDY #0					; 3rd (100ths) digit in accumulator Y
sd100_3:		CMP #100 				; Is A larger or equal than 100?
  				BCS ssub100_3
sd10_3:			CMP #10					; Is A larger or equal than 10?
  				BCS ssub10_3
  				PHA
  				TYA
  				ORA #LCD_NUM_MASK
  				STA ACIA_DATA
  				TXA
  				ORA #LCD_NUM_MASK
  				STA ACIA_DATA
  				PLA
  				ORA #LCD_NUM_MASK
  				STA ACIA_DATA
  				RTS
ssub10_3:		SBC #10
  				INX
  				JMP sd10_3
ssub100_3:		SBC #100
  				INY
  				JMP sd100_3


;-------------------------------------------------------------------------
;  Subroutine to bring cursor to the left by Y amount
;-------------------------------------------------------------------------

LCD_MOVEY_L:	LDA #%00010000			; Cursor left
.lcdmyl0		JSR LCD_CMD_4B
  				DEY
  				BNE .lcdmyl0
  				RTS


;-------------------------------------------------------------------------
;  Subroutine to set LCD cursor absolute position
;  Enter with desired address 0-127 in A 
;-------------------------------------------------------------------------

LCD_SET_POS: 	ORA #%10000000
				JSR LCD_CMD_4B
				RTS	


;-------------------------------------------------------------------------
;  Subroutine to clear LCD
;------------------------------------------------------------------------

LCD_CLEAR: 		LDA #%00000001			; Clear display
  				JSR LCD_CMD_4B	
  				JSR WAIT_LCD 			; LCD is busy after op
  				RTS


;-------------------------------------------------------------------------
;  Subroutine to wait for LCD busy flag to clear
;-------------------------------------------------------------------------

WAIT_LCD:		STZ DDRB         		; Set all pins on PORTB to input
				LDA #SR_IDLE
				STA PORTA 				; Clear all LCD (RS/RW/E) bits

.lbw0: 		 	LDA #(LCD_RW | SR_IDLE)
  				STA PORTA
  				LDA #(LCD_E | LCD_RW | SR_IDLE)
  				STA PORTA
                LDA PORTB             	; Load LCD data register (with busy flag) into A
                PHA 					; Then cycle E again to dump out the AC registers
				LDA #(LCD_RW | SR_IDLE)
  				STA PORTA
  				LDA #(LCD_E | LCD_RW | SR_IDLE)
  				STA PORTA
 				PLA
                AND #LCD_BUSY         	; Mask the LCD busy bit flag
                BNE .lbw0        	 	; If busy bit is NOT clear we repeat check

  				LDA #SR_IDLE 			; Clear all LCD (RS/RW/E) bits
  				STA PORTA 
                LDA #DDRB_BITS         	; Set PORTB to normal direction
                STA DDRB
                RTS


;-------------------------------------------------------------------------
;  Subroutine to do a delay that takes more than 1000 CPU cycles
;  Destroys X
;-------------------------------------------------------------------------

DELAY:			LDX #255
.d1:			DEX
  				CPX #0
  				BNE .d1 
  				RTS


;-------------------------------------------------------------------------
;  Subroutine to send a command to LCD, 8-bit mode, used for init only
;-------------------------------------------------------------------------

LCD_CMD_8B:		STA PORTB
				LDA PORTA				; Get PORTA and clear all LCD control bits
				AND #(~LCD_E & ~LCD_RS & ~LCD_RW & %11111111)
				STA PORTA
				ORA #LCD_E 				; Set E
				STA PORTA
				EOR #LCD_E 				; Clear E
				STA PORTA
				RTS


;-------------------------------------------------------------------------
;  Subroutine to send a command to LCD, 4-bit mode
;  Preserves A
;-------------------------------------------------------------------------

LCD_CMD_4B:		PHA 					; First send 4 MSB
  				LSR A
  				LSR A
  				LSR A
  				LSR A
  				AND #%00001111
  				STA PORTB
				LDA PORTA				; Get PORTA and clear all LCD control bits
				AND #(~LCD_E & ~LCD_RS & ~LCD_RW & %11111111)
				STA PORTA
				ORA #LCD_E 				; Set E
				STA PORTA
				EOR #LCD_E 				; Clear E
				STA PORTA
  				PLA 					; Then send 4 LSB
  				PHA
  				AND #%00001111
  				STA PORTB
				LDA PORTA
				ORA #LCD_E 				; Set E
				STA PORTA
				EOR #LCD_E 				; Clear E
				STA PORTA
  				PLA
  				RTS


;-------------------------------------------------------------------------
;  Subroutine to print whatever to LCD
;-------------------------------------------------------------------------

LCD_PRINT:		PHA  					; First send 4 MSB
  				LSR A
  				LSR A
  				LSR A
  				LSR A
  				AND #%00001111
  				STA PORTB
  				LDA #(LCD_RS | SR_IDLE) 
  				STA PORTA 				; Set RS; Clear RW/E bits
  				LDA #(LCD_RS | LCD_E | SR_IDLE) 
  				STA PORTA 				; Set E bit to send instruction
  				LDA #(LCD_RS | SR_IDLE) 
  				STA PORTA 				; Clear E bits
  				PLA 					; Then send 4 LSB
  				AND #%00001111
  				STA PORTB
  				LDA #(LCD_RS | LCD_E | SR_IDLE) 
  				STA PORTA 				; Set E bit to send instruction
  				LDA #(LCD_RS | SR_IDLE) 
  				STA PORTA 				; Clear E bits
  				RTS


;-------------------------------------------------------------------------
;  Subroutine to print a 3-digit integer to LCD
;-------------------------------------------------------------------------

LCD_P_INT3:		LDX #0 					; 2nd (10ths) digit in accumulator X
  				LDY #0					; 3rd (100ths) digit in accumulator Y

d100_3:			CMP #100 				; Is A larger or equal than 100?
  				BCS sub100_3

d10_3:			CMP #10					; Is A larger or equal than 10?
  				BCS sub10_3
  				PHA
  				TYA
  				ORA #LCD_NUM_MASK
  				JSR LCD_PRINT
  				TXA
  				ORA #LCD_NUM_MASK
  				JSR LCD_PRINT
  				PLA
  				ORA #LCD_NUM_MASK
  				JSR LCD_PRINT
  				RTS

sub10_3:		SBC #10
  				INX
  				JMP d10_3

sub100_3:		SBC #100
  				INY
  				JMP d100_3


;-------------------------------------------------------------------------
;  Subroutine to print a 2-digit integer to LCD
;-------------------------------------------------------------------------

LCD_P_INT2: 	LDX #0 					; 2nd (10ths) digit in accumulator X

d10_2:			CMP #10					; Is A larger or equal than 10?
  				BCS sub10_2
  				PHA
  				TXA
  				ORA #LCD_NUM_MASK
  				JSR LCD_PRINT
  				PLA
  				ORA #LCD_NUM_MASK
  				JSR LCD_PRINT
  				RTS

sub10_2:		SBC #10
  				INX
  				JMP d10_2


;-------------------------------------------------------------------------
;  Subroutine to initialize LCD to 4-bit mode, set it up and clear it
;-------------------------------------------------------------------------

INIT_LCD: 		LDY #2	
.ilcd0			LDA #%00000011			; Write this 3 times to put LCD into a known state
  				JSR LCD_CMD_8B
  				JSR DELAY
  				DEY
  				BPL .ilcd0
				
  				LDA #%00000010
  				JSR LCD_CMD_8B	
  				JSR DELAY
				
  				; LCD is now in 4 bit mode, continue init
  				LDA #%00101000 			; Function set - 4 bit, 2 line, 5x8 font
  				JSR LCD_CMD_4B	
  				JSR WAIT_LCD 			; LCD is busy after op
					
  				LDA #%00001110			; Display control - display on, cursor on, blink off
  				JSR LCD_CMD_4B	
  				JSR WAIT_LCD 			; LCD is busy after op
					
  				LDA #%00000110			; Entry mode set - increment and shift cursor, don't shift display
  				JSR LCD_CMD_4B	
  				JSR WAIT_LCD 			; LCD is busy after op
					
  				JSR LCD_CLEAR			; Clear display
  				RTS


;-------------------------------------------------------------------------
;  Subroutine to get/read ADC values through HW a shift register
;-------------------------------------------------------------------------

GET_ADC:		LDA #SR_IDLE 			; SR to parallel (listen) mode, ADC idling
  				STA PORTA
  				LDA #SR_CONVERT 		; WD low for min. 600 ns triggers conversion on ADC, keep SR listening 
  				STA PORTA 
  				LDA #SR_IDLE			; WR high again, ADC has data available in 600 ns from now, SR listening
  				STA PORTA
  				LDA #SR_LATCH			; Latch SR, serial mode
  				STA PORTA
  				LDA SR 					; Read SR from previous round. This triggers new async SR read
  				RTS


;-------------------------------------------------------------------------
;  Application to show temperature and time
;-------------------------------------------------------------------------

APP_TEMP_TIME: 	STZ V_RTC_SEC
				STZ V_RTC_MIN
				STZ V_RTC_HR
				JMP DRAW_TEMP_TIME


;-------------------------------------------------------------------------
;  Subroutine to get and display temperature and time
;-------------------------------------------------------------------------

DRAW_TEMP_TIME:	JSR GET_ADC 			; Read out data in SR and print it			
  				JSR P_TEMP_C 			; Print using calibration table
  				LDA #%11011111 			; Special symbol '°'
  				JSR LCD_PRINT
  				LDA #'C'
  				JSR LCD_PRINT
				
  				LDA #%00010100			; Move display to the right (space)
  				JSR LCD_CMD_4B
				
  				LDA $2 					; Get RTC seconds and print them
  				JSR LCD_P_INT2
  				LDA #'h'
  				JSR LCD_PRINT
				
  				LDA $1 					; Get RTC seconds and print them
  				JSR LCD_P_INT2
  				LDA #'m'
  				JSR LCD_PRINT
					
  				LDA $0 					; Get RTC seconds and print them
  				JSR LCD_P_INT2
  				LDA #'s'
  				JSR LCD_PRINT

				WAI 					; Sleep CPU until next RTC tick
					
  				LDX #16 				; Move display to the start
  				LDA #%00010000			; Cursor left
.dtt0:			JSR LCD_CMD_4B
  				DEX
  				BNE .dtt0

  				JMP DRAW_TEMP_TIME 		; Loop


;-------------------------------------------------------------------------
;  Subroutine to print a temperature in Celsius, with raw value in A
;-------------------------------------------------------------------------

P_TEMP_C:		TAX
  				PHA
  				LDA LUT_ADC_int, X
  				JSR LCD_P_INT2
  				LDA #'.'
  				JSR LCD_PRINT
  				PLA
  				TAX
  				LDA LUT_ADC_dec, X
  				ORA #LCD_NUM_MASK
  				JSR LCD_PRINT
  				RTS


;-------------------------------------------------------------------------
;  Application to test serial port input/output capability
;-------------------------------------------------------------------------

APP_SER_TEST: 	LDA #%00000001			; Clear display
  				JSR LCD_CMD_4B	
  				JSR WAIT_LCD 			; LCD is busy after op
  				LDA #'>'
  				JSR LCD_PRINT
  				STZ S_DATA_RDY 			; Prepare serial print variables
  				STZ S_IN_BYTE
  				STZ S_BYTE_COUNT
  				JMP SER_TEST_MAIN


;-------------------------------------------------------------------------
;  Subroutine to continuously print whatever is in the serial port
;-------------------------------------------------------------------------

SER_TEST_MAIN:	LDA ACIA_STATUS 		; Is new data available?
				AND #%00001000
				BEQ SER_TEST_MAIN 		; If no, check again
				LDA ACIA_DATA 			; If yes, load input byte
				CMP #10
				BNE .sit0 				; Continue to counting bytes and printing if not \n

				LDA #>str_rcvd 		 	; Got \n, so report received byte count back to serial..
  				STA V_P_STR_HI	
  				LDA #<str_rcvd
  				STA V_P_STR_LO
  				JSR SER_P_STR
				LDA S_BYTE_COUNT
				JSR SER_P_INT3
				LDA #>str_bytes
  				STA V_P_STR_HI	
  				LDA #<str_bytes
  				STA V_P_STR_LO
  				JSR SER_P_STR
  				LDX #15 				; Delay 1000 ms
				JSR DELAY_X	
				JMP APP_SER_TEST		; Then reset app (clear screen)

.sit0 			INC S_BYTE_COUNT 	 	; Increase byte count (0-255)
				JSR LCD_PRINT 			; Any other char, so print it to LCD
				STZ S_DATA_RDY 			; Clear data available bit
				JMP SER_TEST_MAIN


;-------------------------------------------------------------------------
;  String storage
;-------------------------------------------------------------------------

str_temp_header:
	db "Temp:  Uptime:                          ",255

str_uboot_title1:
	db "65c02 MicroBoot",255

str_uboot_title2:
	db "Version 0.2.2",255

str_credits1:
	db "Juha Koljonen",255

str_credits2:
	db "Silicon Valley",255

str_serialout_title:
	db "Sending..",255

str_rcvd:
	db "Got ",255

str_bytes:
	db " byte(s)",10,255

str_blocks:
	db " block(s)",255

str_jmodem:
	db "* ~~ JMODEM ~~ *",255

str_ready_to_load:
	db "Ready to receive",255

str_loading:
	db "Receiving data..",255

str_block_num:
	db "Block #   ",255

str_tfer_fail:
	db "Transfer err ",255

str_success:
	db "Success!",255

str_m0:
	db "Load & Run",255

str_m1:
	db "Load",255

str_m2:
	db "Run",255

str_m3:
	db "EEPROM Apps",255

str_b0:
	db "Temp and time",255

str_b1:
	db "Test UART I/O",255

str_b2:
	db "Back",255

;-------------------------------------------------------------------------
;  Tables
;-------------------------------------------------------------------------

LUT_ADC_int:
	db 0,0,0,0,0,1,1,1,1,1,2,2,2,2,2,3,3,3,3,3,4,4,4,4,4,5,5,5,5,5,6,6,6,6,6,7,7,7,7,7,8,8,8,8,8,9,9,9,9,9,10,10,10,10,10,11,11,11,11,11,12,12,12,12,12,13,13,13,13,13,14,14,14,14,14,15,15,15,15,15,16,16,16,16,16,17,17,17,17,17,18,18,18,18,18,19,19,19,19,19,20,20,20,20,20,21,21,21,21,21,22,22,22,22,22,23,23,23,23,23,24,24,24,24,24,25,25,25,25,25,26,26,26,26,26,27,27,27,27,27,28,28,28,28,28,29,29,29,29,29,30,30,30,30,30,31,31,31,31,31,32,32,32,32,32,33,33,33,33,33,34,34,34,34,34,35,35,35,35,35,36,36,36,36,36,37,37,37,37,37,38,38,38,38,38,39,39,39,39,39,40,40,40,40,40,41,41,41,41,41,42,42,42,42,42,43,43,43,43,43,44,44,44,44,44,45,45,45,45,45,46,46,46,46,46,47,47,47,47,47,48,48,48,48,48,49,49,49,49,49,50,50,50,50,50,51

LUT_ADC_dec:
	db 0,2,4,6,8,0,2,4,6,8,0,2,4,6,8,0,2,4,6,8,0,2,4,6,8,0,2,4,6,8,0,2,4,6,8,0,2,4,6,8,0,2,4,6,8,0,2,4,6,8,0,2,4,6,8,0,2,4,6,8,0,2,4,6,8,0,2,4,6,8,0,2,4,6,8,0,2,4,6,8,0,1,4,6,8,0,1,4,6,8,0,1,4,6,8,0,2,4,6,8,0,2,4,6,8,0,2,4,6,8,0,2,4,6,8,0,2,4,6,8,0,2,4,6,8,0,2,4,6,8,0,2,4,6,8,0,2,4,6,8,0,2,4,6,8,0,2,4,6,8,0,2,4,6,8,0,2,4,6,8,0,2,3,6,8,0,2,3,6,8,0,2,3,6,8,0,2,3,6,8,0,2,3,6,8,0,2,3,6,8,0,2,4,6,8,0,2,4,6,8,0,2,4,6,8,0,2,4,6,8,0,2,4,6,8,0,2,4,6,8,0,2,4,6,8,0,2,4,6,8,0,2,4,6,8,0,2,4,6,8,0,2,4,6,8,0,2,4,6,8,0,2,4,6,8,0

TBL_JUMP: 		
	.word APP_LOAD_RUN, APP_LOAD, APP_RUN, GOTO_BMENU				; Main menu items
	.word APP_TEMP_TIME, APP_SER_TEST, GOTO_MMENU					; Built in apps

TBL_MMENU_ITEMS:
	.word str_m0, str_m1, str_m2, str_m3

TBL_BMENU_ITEMS:
	.word str_b0, str_b1, str_b2

;-------------------------------------------------------------------------
;  65c02 CPU vectors
;-------------------------------------------------------------------------

				.org   $fffa  			; Insert at $FFFA
NMIVEC: 		.word  NMI  			; Make the NMI vector point to NMI ISR
RESVEC: 		.word  RESET    		; Make the reset vector point to the reset routine
IRQVEC: 		.word  IRQ  			; Make the IRQ vector point to IRQ ISR
