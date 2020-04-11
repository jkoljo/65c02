#define RESTART_ADDR 0xE000ED0C
#define READ_RESTART() (*(volatile uint32_t *)RESTART_ADDR)
#define WRITE_RESTART(val) ((*(volatile uint32_t *)RESTART_ADDR) = (val))

#define ADDR_LINES 16
#define DATA_LINES 8
#define ADDR_ACIA_DATA    0x5000 // Data
#define ADDR_ACIA_STATUS  0x5001 // Status (read op reads status word, write resets chip): 
                                 // B7 IRQ interrupt (high = interrupt occurred)
                                 // B6 DSRB data set ready (low = ready, set to 0)
                                 // B5 DCDB data carrier detect (low = detected, set to 0)
                                 // B4 Transmitter data reg empty (high = empty)
                                 // B3 Receiver data reg full (high = full, byte available)
                                 // B0-2 errors (overrun, framing, parity)
#define ADDR_ACIA_CMD     0x5002 // Command:
                                 // B7&B6 parity mode, ignore, 11 to disable
                                 // B5 parity enabled, ignore, 0 to disable
                                 // B4 RCVR echo mode, 0 for normal mode
                                 // B3&B2 transmitter interrupt ctrl: 01 for enabled, 1x for disabled 
                                 // B1 receiver interrupt disabled, 0 for enabled
                                 // B0 DTR data terminal ready, 1 for ready state
#define ADDR_ACIA_CTRL    0x5003 // Control: RS232 specs -> ignore
                                 // 65c51 good spec is 00011111

#define ACIA_DEFAULT_STATUS 0b00000000
#define ACIA_DEFAULT_CMD 0b11001111

// Status byte masks
const uint8_t IRQ_MASK = 1 << 7;
const uint8_t TX_DATAEMPTY_MASK = 1 << 4;
const uint8_t RX_DATAFULL_MASK = 1 << 3;

// Command byte masks
const uint8_t RX_IRQ_DISABLE_MASK = 1 << 1;
const uint8_t TX_IRQ_DISABLE_MASK = 1 << 3;

volatile uint8_t ACIA_status = ACIA_DEFAULT_STATUS;
volatile uint8_t ACIA_cmd = ACIA_DEFAULT_CMD;

const uint8_t led_irq = 24;
const uint8_t led_probe = 25;
const uint8_t led_serial = 26;
const uint8_t IRQ = 30; // NMI Interrupt for 65c02
const uint8_t phi2 = 31;
const uint8_t rw = 32;
const uint8_t oe = 33;

const uint8_t a0 = 7;     // First level converter bank
const uint8_t a1 = 6;
const uint8_t a2 = 5;
const uint8_t a3 = 4;
const uint8_t a4 = 16;
const uint8_t a5 = 17;
const uint8_t a6 = 18;
const uint8_t a7 = 19;

const uint8_t a8 = 20;     // Second level converter bank
const uint8_t a9 = 21;
const uint8_t a10 = 22;
const uint8_t a11 = 23;
const uint8_t a12 = 3;
const uint8_t a13 = 2;
const uint8_t a14 = 1;
const uint8_t a15 = 0;

const uint8_t d0 = 15;     // Third level converter bank
const uint8_t d1 = 14;
const uint8_t d2 = 13;
const uint8_t d3 = 12;
const uint8_t d4 = 11;
const uint8_t d5 = 10;
const uint8_t d6 = 9;
const uint8_t d7 = 8;

const uint8_t addr_lines[ADDR_LINES] =  {a0, a1, a2, a3, a4, a5, a6, a7,
                          a8, a9, a10, a11, a12, a13, a14, a15};

const uint8_t data_lines[DATA_LINES]  =  {d0, d1, d2, d3, d4, d5, d6, d7};

volatile uint16_t addr = 0;      // Current address
volatile uint8_t data_in = 0;    // Last data in
volatile uint8_t data_out = 0;   // Last data out

volatile bool flag_reset = false;
volatile bool flag_ACIA_DATA = false;
volatile bool flag_ACIA_STATUS = false;
volatile bool flag_ACIA_CMD = false;
volatile bool flag_ACIA_CTRL = false;
volatile bool flag_SYNC_ERR = false;
volatile uint8_t sync_err_count = 0;
volatile bool sync_err_rw = 0;
volatile uint16_t sync_err_addr = 0;

uint16_t readAddrLines(void);
uint8_t readDataLines(void);

elapsedMillis last_ser_led_update = 0;
elapsedMillis last_irq_led_update = 0;
elapsedMillis last_probe_led_update = 0;
const uint16_t SER_LED_UPDATE_RATE = 20;
const uint16_t IRQ_LED_UPDATE_RATE = 20;
const uint16_t PROBE_LED_UPDATE_RATE = 500;

void setup() {
  cli();
  pinMode(led_irq, OUTPUT);
  pinMode(led_probe, OUTPUT);
  pinMode(led_serial, OUTPUT);
  pinMode(oe, OUTPUT);
  pinMode(phi2, INPUT);
  pinMode(rw, INPUT);
  
  digitalWriteFast(IRQ, HIGH);
  pinMode(IRQ, OUTPUT);
  digitalWriteFast(IRQ, HIGH);

  setAddrLineDir(INPUT);    // Set I/O directions
  setDataLineDirInFast();   
  digitalWriteFast(oe, HIGH); // Enable level converters

  Serial.begin(0);
  Serial.flush();
  Serial.println("65c02 Co-Processor v0.1.1 - Juha Koljonen 2020");

  // Wait for PHI2 to fall before proceeding
  while (!digitalReadFast(phi2)) {}   // Wait if clock is low..
  while (digitalReadFast(phi2)) {}    // Wait clock high period
  attachInterrupt(phi2, ISR, RISING);
  NVIC_SET_PRIORITY(IRQ_GPIO6789, 0); // Raise PHI2 (all gpio) interrupt priority
  sei();                               // Go!
}

void loop() {
  if (last_ser_led_update > SER_LED_UPDATE_RATE) {
    digitalWriteFast(led_serial, LOW);
    last_ser_led_update = 0;
  }

  if (last_probe_led_update > PROBE_LED_UPDATE_RATE) {
    digitalWriteFast(led_probe, HIGH); 
    last_probe_led_update = 0;
  }

  if (last_irq_led_update > IRQ_LED_UPDATE_RATE) {
    digitalWriteFast(led_irq, LOW);
    last_irq_led_update = 0;
  }

  if (Serial.availableForWrite()) {
    ACIA_status |= TX_DATAEMPTY_MASK;
  } else {
    ACIA_status &= ~TX_DATAEMPTY_MASK;
  }

  if ((Serial.available() >=1) && !(ACIA_status & RX_DATAFULL_MASK)) {
    // Serial data is available and incoming buffer is not full
    data_out = Serial.read();     // Prepare data to send to 65c02
    ACIA_status |= RX_DATAFULL_MASK;
    if (!(ACIA_cmd & RX_IRQ_DISABLE_MASK)) {
      ACIA_status |= IRQ_MASK;
    }
  }

  if (flag_reset) {
    Serial.println("65c02 Reset");
    flag_reset = false;
  } else if (flag_ACIA_CTRL) {
    Serial.println("WARNING: ACIA ctrl register unsupported");
    flag_ACIA_CTRL = false;
  }

  if (flag_SYNC_ERR) {
    if (sync_err_count++ < 10) {
      Serial.print("WARNING: Sync lag, addr ");
      Serial.print(sync_err_addr, HEX);
      Serial.println(sync_err_rw ? " read" : " write");
    } else {
      Serial.println("ERR: Syncronization lost. HALT.");
      digitalWriteFast(led_probe, LOW);
      delay(100);
      cli();
      while(1) {delay(100);}
    }
    flag_SYNC_ERR = false;
  }

  if (digitalReadFast(IRQ) && (ACIA_status & IRQ_MASK)) {
    digitalWriteFast(led_irq, HIGH);
    last_irq_led_update = 0;
    digitalWriteFast(IRQ, LOW);
  }

  delayMicroseconds(5); // Slow down system to give Teensy time to handle USB Serial
}

FASTRUN void ISR() {
  for (int i=0; i< 10; i++) {         // Wait for inputs to stabilize, TXB0108PWR needs 4ns
    __asm__ volatile("nop" "\n\t");
  }
  bool new_data_to_tx = false;
  uint8_t mcu_reading = digitalReadFast(rw);
  addr = readAddrLinesFast();
  
  switch(addr) {
    case ADDR_ACIA_DATA:
      if (mcu_reading) {
        setDataLineDirOutFast();
        writeDataLinesFast(data_out);
        digitalWriteFast(IRQ, HIGH);  // Drop IRQ request
        ACIA_status &= ~IRQ_MASK;
        ACIA_status &= ~RX_DATAFULL_MASK;
      } else {
        data_in = readDataLinesFast();
        new_data_to_tx = true;
      }
      digitalWriteFast(led_serial, HIGH);
      last_ser_led_update = 0;
      break;
      
    case ADDR_ACIA_STATUS:
      if (mcu_reading) {
        setDataLineDirOutFast();
        writeDataLinesFast(ACIA_status);
      } else {
        // Writing status word = ACIA reset
        initializeACIA();
      }
      break;
      
    case ADDR_ACIA_CMD:
      if (mcu_reading) {
        setDataLineDirOutFast();
        writeDataLinesFast(ACIA_cmd);
      } else {
        ACIA_cmd = readDataLinesFast();
      }
      break;
      
    case ADDR_ACIA_CTRL:
      flag_ACIA_CTRL = true;
      break;
      
    case 0xFFFC:  // Reset vector
      flag_reset = true;
      break;
  }
  
  if (!digitalReadFast(phi2)) {
    digitalWriteFast(led_probe, LOW);
    last_probe_led_update = 0;
    flag_SYNC_ERR = true;
    sync_err_addr = addr;
    sync_err_rw = mcu_reading;
  }

  if (new_data_to_tx) Serial.print((char)data_in);

  while(digitalReadFast(phi2)) {}   // Could count free CPU cycles here
  if (mcu_reading) { // Restore data line direction
    setDataLineDirInFast();
  }
}

void printDebugData() {
  Serial.print(addr, HEX);
  Serial.print("\t");
  Serial.print(data_in, HEX);
  Serial.print("\n");
}

void initializeACIA() {
  Serial.flush();
  ACIA_status = ACIA_DEFAULT_STATUS;
  ACIA_cmd = ACIA_DEFAULT_CMD;
  digitalWriteFast(IRQ, HIGH);
}

void setAddrLineDir(uint8_t mode) {
  for (int i = 0; i < ADDR_LINES; i++) {
    pinMode(addr_lines[i], mode);
  }
}

void setDataLineDirOutFast() { //DDRREG bit high -> output
  CORE_PIN8_DDRREG |= CORE_PIN8_BITMASK;
  CORE_PIN9_DDRREG |= CORE_PIN9_BITMASK;
  CORE_PIN10_DDRREG |= CORE_PIN10_BITMASK;
  CORE_PIN11_DDRREG |= CORE_PIN11_BITMASK;
  CORE_PIN12_DDRREG |= CORE_PIN12_BITMASK;
  CORE_PIN13_DDRREG |= CORE_PIN13_BITMASK;
  CORE_PIN14_DDRREG |= CORE_PIN14_BITMASK;
  CORE_PIN15_DDRREG |= CORE_PIN15_BITMASK;
}

void setDataLineDirInFast() { //DDRREG bit low -> input 
  CORE_PIN8_DDRREG &= ~CORE_PIN8_BITMASK;
  CORE_PIN9_DDRREG &= ~CORE_PIN9_BITMASK;
  CORE_PIN10_DDRREG &= ~CORE_PIN10_BITMASK;
  CORE_PIN11_DDRREG &= ~CORE_PIN11_BITMASK;
  CORE_PIN12_DDRREG &= ~CORE_PIN12_BITMASK;
  CORE_PIN13_DDRREG &= ~CORE_PIN13_BITMASK;
  CORE_PIN14_DDRREG &= ~CORE_PIN14_BITMASK;
  CORE_PIN15_DDRREG &= ~CORE_PIN15_BITMASK;
}

void writeDataLinesFast(uint8_t data) {
  if (data & (1)) CORE_PIN15_PORTSET = CORE_PIN15_BITMASK;
  else CORE_PIN15_PORTCLEAR = CORE_PIN15_BITMASK;

  if (data & (1 << 1)) CORE_PIN14_PORTSET = CORE_PIN14_BITMASK;
  else CORE_PIN14_PORTCLEAR = CORE_PIN14_BITMASK;

  if (data & (1 << 2)) CORE_PIN13_PORTSET = CORE_PIN13_BITMASK;
  else CORE_PIN13_PORTCLEAR = CORE_PIN13_BITMASK;

  if (data & (1 << 3)) CORE_PIN12_PORTSET = CORE_PIN12_BITMASK;
  else CORE_PIN12_PORTCLEAR = CORE_PIN12_BITMASK;

  if (data & (1 << 4)) CORE_PIN11_PORTSET = CORE_PIN11_BITMASK;
  else CORE_PIN11_PORTCLEAR = CORE_PIN11_BITMASK;

  if (data & (1 << 5)) CORE_PIN10_PORTSET = CORE_PIN10_BITMASK;
  else CORE_PIN10_PORTCLEAR = CORE_PIN10_BITMASK;

  if (data & (1 << 6)) CORE_PIN9_PORTSET = CORE_PIN9_BITMASK;
  else CORE_PIN9_PORTCLEAR = CORE_PIN9_BITMASK;

  if (data & (1 << 7)) CORE_PIN8_PORTSET = CORE_PIN8_BITMASK;
  else CORE_PIN8_PORTCLEAR = CORE_PIN8_BITMASK;
}

uint16_t readAddrLinesFast(void) {
return   ((CORE_PIN7_PINREG  & CORE_PIN7_BITMASK)  ? 1 : 0)       | 
        (((CORE_PIN6_PINREG  & CORE_PIN6_BITMASK)  ? 1 : 0) << 1)  |
        (((CORE_PIN5_PINREG  & CORE_PIN5_BITMASK)  ? 1 : 0) << 2)  |
        (((CORE_PIN4_PINREG  & CORE_PIN4_BITMASK)  ? 1 : 0) << 3)  |
        (((CORE_PIN16_PINREG & CORE_PIN16_BITMASK) ? 1 : 0) << 4)  |
        (((CORE_PIN17_PINREG & CORE_PIN17_BITMASK) ? 1 : 0) << 5)  |
        (((CORE_PIN18_PINREG & CORE_PIN18_BITMASK) ? 1 : 0) << 6)  |
        (((CORE_PIN19_PINREG & CORE_PIN19_BITMASK) ? 1 : 0) << 7)  | 
        (((CORE_PIN20_PINREG & CORE_PIN20_BITMASK) ? 1 : 0) << 8)  |
        (((CORE_PIN21_PINREG & CORE_PIN21_BITMASK) ? 1 : 0) << 9)  |
        (((CORE_PIN22_PINREG & CORE_PIN22_BITMASK) ? 1 : 0) << 10) |
        (((CORE_PIN23_PINREG & CORE_PIN23_BITMASK) ? 1 : 0) << 11) |
        (((CORE_PIN3_PINREG  & CORE_PIN3_BITMASK)  ? 1 : 0) << 12) |
        (((CORE_PIN2_PINREG  & CORE_PIN2_BITMASK)  ? 1 : 0) << 13) |
        (((CORE_PIN1_PINREG  & CORE_PIN1_BITMASK)  ? 1 : 0) << 14) |
        (((CORE_PIN0_PINREG  & CORE_PIN0_BITMASK)  ? 1 : 0) << 15);
}

uint8_t readDataLinesFast(void) {
return  (( CORE_PIN15_PINREG & CORE_PIN15_BITMASK) ? 1 : 0)       | 
        (((CORE_PIN14_PINREG & CORE_PIN14_BITMASK) ? 1 : 0) << 1) |
        (((CORE_PIN13_PINREG & CORE_PIN13_BITMASK) ? 1 : 0) << 2) |
        (((CORE_PIN12_PINREG & CORE_PIN12_BITMASK) ? 1 : 0) << 3) |
        (((CORE_PIN11_PINREG & CORE_PIN11_BITMASK) ? 1 : 0) << 4) |
        (((CORE_PIN10_PINREG & CORE_PIN10_BITMASK) ? 1 : 0) << 5) |
        (((CORE_PIN9_PINREG  & CORE_PIN9_BITMASK)  ? 1 : 0) << 6) |
        (((CORE_PIN8_PINREG  & CORE_PIN8_BITMASK)  ? 1 : 0) << 7); 
}

/*uint8_t readDataLines(void) {
  uint8_t temp_data = 0;
  for (int i=0; i<8; i++) {
    temp_data |= digitalReadFast(data_lines[i]) << i;
  }
  return temp_data;
}*/

/*void writeDataLines(uint8_t data) {
  for (int i = 0; i < DATA_LINES; i++) {
      digitalWriteFast(data_lines[i], data & (1 << i));
  }
}*/

/*void setDataLineDir(uint8_t mode) {
  digitalWriteFast(oe, LOW);
  for (int i = 0; i < DATA_LINES; i++) {
    pinMode(data_lines[i], mode);
  }
}*/

/*uint16_t readAddrLines(void) {
  uint16_t temp_addr = 0;
  for (int i=0; i<16; i++) {
    temp_addr |= digitalReadFast(addr_lines[i]) << i;
  }
  return temp_addr;
}*/
