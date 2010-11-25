#include <TwiMaster.h>
#include <Sleep.h>
#include <eeprom_24aa1025.h>

TwiMaster twi;

#define DS3231M_DEV_ID   0x68

#define TC74_DEV_ID     B1001011
#define TC74_TEMP_ADDR  0x00
#define TC74_CFG_ADDR   0x01
#define TC74_STANDBY    0x01
#define TC74_NORMAL     0x00


typedef struct {
  uint8_t year;
  uint8_t  month;
  uint8_t  date;
  uint8_t  hour;
  uint8_t  minutes;
  uint8_t  seconds;
} 
time_type;

typedef struct {
  uint16_t  sample;
  time_type time;
  uint8_t   temperature;
} 
data_record_type;

uint16_t         total_samples;
time_type        current_time;
data_record_type current_sample;

#define UNDEFINED   0
#define EMBEDDED    1
#define INTERACTIVE 2

uint8_t count_down = 10;
uint8_t mode = UNDEFINED;

const uint32_t TOTAL_SAMPLES_ADDRESS = 0x0;
const uint32_t CURRENT_TIME_ADDRESS  = TOTAL_SAMPLES_ADDRESS + sizeof(total_samples);
const uint32_t SAMPLE_DATA_ADDRESS   = CURRENT_TIME_ADDRESS + sizeof(current_time);

// DS3231M stuff
#define SECONDS_ADDR      0x00
#define MINUTES_ADDR      0x01
#define HOURS_ADDR        0x02
#define DAY_ADDR          0x03
#define DATE_ADDR         0x04
#define MONTH_ADDR        0x05
#define YEAR_ADDR         0x06
#define A1_SECONDS_ADDR   0x07
#define A1_MINUTES_ADDR   0x08
#define A1_HOURS_ADDR     0x09
#define A1_DATE_ADDR      0x0A
#define A2_MINUTES_ADDR   0x0B
#define A2_HOURS_ADDR     0x0C
#define A2_DATE_ADDR      0x0D
#define CONTROL_ADDR      0x0E
#define STATUS_ADDR       0x0F
#define AGING_OFFSET_ADDR 0x10
#define TEMP_MSB_ADDR     0x11
#define TEMP_LSB_ADDR     0x12

static uint8_t ds3231m_get(uint8_t reg) {
  if (twi.start(DS3231M_DEV_ID, I2C_WRITE)) {
    twi.write(reg);
    twi.start(DS3231M_DEV_ID, I2C_READ);
    uint8_t b = twi.read(true);
    twi.stop();
    return b;
  } 
  else {
    Serial.println("clock not responding.");
    return 0;
  }
}

static bool ds3231m_set(uint8_t reg, uint8_t val) {
  if (twi.start(DS3231M_DEV_ID, I2C_WRITE)) {
    twi.write(reg);
    twi.write(val);
    twi.stop();
    return true;
  } 
  else {
    Serial.println("clock not responding.");
    return false;
  }
}

void clock_init() {
  uint8_t b = 0;
  // set control register
  b = 0b00011101; // set INTCN and A1IE true)
  ds3231m_set(CONTROL_ADDR, b);
  b = 0b00000000; // set Oscillator stop flag to false
  ds3231m_set(STATUS_ADDR, b);

  // set alarm to go off once an hour, on the hour
  ds3231m_set(A1_SECONDS_ADDR, 0b00000000); // care about the seconds matching
  ds3231m_set(A1_MINUTES_ADDR, 0b00000000); // care about the minutes matching
  ds3231m_set(A1_HOURS_ADDR,   0b10000000); // don't care about the hours matching
  ds3231m_set(A1_DATE_ADDR,    0b10000000); // don't care about the date matching
}

void clock_print_time(const time_type& t, bool newline = true) {
  Serial.print("20");
  if (t.year < 10) {
    Serial.print("0");
  }
  Serial.print(t.year, DEC); 
  Serial.print("-"); 
  if (t.month < 10) {
    Serial.print("0");
  }
  Serial.print(t.month, DEC); 
  Serial.print("-"); 
  if (t.date < 10) {
    Serial.print("0");
  }
  Serial.print(t.date, DEC); 
  Serial.print(" ");
  if (t.hour < 10) {
    Serial.print("0");
  }
  Serial.print(t.hour, DEC); 
  Serial.print(":");
  if (t.minutes < 10) {
    Serial.print("0");
  }
  Serial.print(t.minutes, DEC); 
  Serial.print(":");
  if (t.seconds < 10) {
    Serial.print("0");
  }
  if (newline) {
    Serial.println(t.seconds, DEC);  
  } 
  else {
    Serial.print(t.seconds, DEC);
  }
}

static void clock_set_time(const time_type& t) {
  // convert decimal to bcd
  uint8_t seconds = (((t.seconds / 10) << 4) & 0b01110000) + (t.seconds % 10);
  uint8_t minutes = (((t.minutes / 10) << 4) & 0b01110000) + (t.minutes % 10);
  uint8_t hours   = (((t.hour    / 10) << 4) & 0b00110000) + (t.hour    % 10); // this will set the 24-hour bit to 0, which we want
  uint8_t date    = (((t.date    / 10) << 4) & 0b00110000) + (t.date    % 10);
  uint8_t month   = (((t.month   / 10) << 4) & 0b00010000) + (t.month   % 10);
  uint8_t year    = (((t.year    / 10) << 4) & 0b11110000) + (t.year    % 10);

  if (twi.start(DS3231M_DEV_ID, I2C_WRITE)) {
    twi.write(SECONDS_ADDR); // set address
    twi.write(seconds);
    twi.write(minutes);
    twi.write(hours);
    twi.write(1); // don't care about day of the week
    twi.write(date);
    twi.write(month);
    twi.write(year);
    twi.stop();
  } 
  else {
    Serial.println("clock not responding.");
  }
}

static void clock_get_time(time_type& t) {
  if (twi.start(DS3231M_DEV_ID, I2C_WRITE)) {
    twi.write(SECONDS_ADDR);
    twi.start(DS3231M_DEV_ID, I2C_READ);
    uint8_t seconds = twi.read(false);
    uint8_t minutes = twi.read(false);
    uint8_t hours   = twi.read(false);
    uint8_t junk    = twi.read(false); // don't care about day of the week
    uint8_t date    = twi.read(false);
    uint8_t month   = twi.read(false);
    uint8_t year    = twi.read(true);
    twi.stop();

    // convert bcd to decimal
    t.seconds = ((((seconds & 0b01110000)>>4)*10) + (seconds & 0b00001111));
    t.minutes = ((((minutes & 0b01110000)>>4)*10) + (minutes & 0b00001111));
    t.hour    = ((((hours   & 0b00110000)>>4)*10) + (hours   & 0b00001111));
    t.date    = ((((date    & 0b00110000)>>4)*10) + (date    & 0b00001111));
    t.month   = ((((month   & 0b00010000)>>4)*10) + (month   & 0b00001111));
    t.year    = ((((year    & 0b11110000)>>4)*10) + (year    & 0b00001111));

  } 
  else {
    Serial.println("clock not responding.");
  }
}

void clock_set_year(uint8_t year) { 
  current_time.year = year;
  clock_set_time(current_time);
}
void clock_set_month(uint8_t month) {   
  current_time.month = month;
  clock_set_time(current_time);
}
void clock_set_day(uint8_t day) {   
  current_time.date = day;
  clock_set_time(current_time);
}
void clock_set_hour(uint8_t hour) {   
  current_time.hour = hour;
  clock_set_time(current_time);
}
void clock_set_minutes(uint8_t minutes) {  
  current_time.minutes = minutes;
  clock_set_time(current_time);
}
void clock_set_seconds(uint8_t seconds) {   
  current_time.seconds = seconds;
  clock_set_time(current_time);
}

void usage() {
  Serial.println("Commands: ");
  Serial.println("H   - print this help message");
  Serial.println("E   - enter EMBEDDED mode");
  Serial.println("x   - erase the EEPROM");
  Serial.println("Y## - Set the year to the given 2-digit number");
  Serial.println("M## - Set the month to the given 2-digit number");
  Serial.println("D## - Set the day to the given 2-digit number");
  Serial.println("h## - Set the hour to the given 2-digit number");
  Serial.println("m## - Set the minute to the given 2-digit number");
  Serial.println("s## - Set the second to the given 2-digit number");
  Serial.println("TYYMMDDHHMMSS - Set the year to YY-MM-DD and the time to HH:MM:SS");
  Serial.println("p   - Print all of the stored data");
  Serial.println("r   - Print current temperature");
  Serial.println("t   - Print the current time");
  Serial.println("n   - Print the number of samples taken");
  Serial.println("l   - Print the latest sample");
}

uint8_t getNumber(uint8_t limit, uint8_t bytes = 0) {
  uint8_t val = 0;
  for (uint8_t i = 0; (bytes == 0 || i < bytes) && Serial.available(); i++ ) {
    uint8_t num = Serial.read() - '0';
    val = val*10+num;
    if (val > limit) {
      val = val % limit;
    }
  }
  return val; 
}

void printSample(const data_record_type& s) {
  Serial.print(s.sample);
  Serial.print(",\""); 
  clock_print_time(s.time, false); 
  Serial.print("\","); 
  Serial.print(s.time.year, DEC); 
  Serial.print(","); 
  Serial.print(s.time.month, DEC); 
  Serial.print(","); 
  Serial.print(s.time.date, DEC); 
  Serial.print(",");
  Serial.print(s.time.hour, DEC); 
  Serial.print(","); 
  Serial.print(s.time.minutes, DEC); 
  Serial.print(","); 
  Serial.print(s.time.seconds, DEC); 
  Serial.print(",");
  Serial.println(s.temperature, DEC);
}

void dumpData() {
  // update total samples
  i2c_eeprom_read_buffer(TOTAL_SAMPLES_ADDRESS, (uint8_t*)&total_samples, sizeof(total_samples));
  Serial.println("sample_number,date_time,year,month,day,hour,minutes,seconds,temperature");
  data_record_type s;
  uint32_t addr = SAMPLE_DATA_ADDRESS;
  for (uint16_t i = 0; i < total_samples; i++) {
    i2c_eeprom_read_buffer(addr, (uint8_t*)&s, sizeof(s));
    printSample(s);
    // increment address for next read
    addr = addr + sizeof(s);
  }
}

void processCommands() {
  while (Serial.available() > 0) {
    if (mode == UNDEFINED) {
      Serial.println("Entering INTERACTIVE mode.");
    }
    mode = INTERACTIVE; // set the mode so we stay in 
    uint8_t b = Serial.read();
    switch (b) {
    case 'x':
      clock_get_time(current_time);
      total_samples = 0;
      current_sample.sample      = 0;
      current_sample.time        = current_time;
      current_sample.temperature = 0;

      i2c_eeprom_erase();
      break;

    case 'E':
      Serial.println("Entering EMBEDDED mode.");
      mode = EMBEDDED;
      break;

    case 'T': 
      {
        time_type t;
        t.year    = getNumber(100, 2);
        t.month   = getNumber(12, 2);
        t.date    = getNumber(31, 2);
        t.hour    = getNumber(23, 2);
        t.minutes = getNumber(59, 2);
        t.seconds = getNumber(59, 2);
        clock_set_time(t);
        break;
      }

    case 'Y': 
      clock_set_year(getNumber(100, 2));
      break;

    case 'M': 
      clock_set_month(getNumber(12, 2));
      break;

    case 'D': 
      clock_set_day(getNumber(31, 2));
      break;

    case 'h': 
      clock_set_hour(getNumber(23, 2));
      break;

    case 'm': 
      clock_set_minutes(getNumber(59, 2));
      break;
      
    case 'r':
      Serial.print("Current temperature: ");
      Serial.println(getTemp(), DEC);
      break;

    case 's': 
      clock_set_seconds(getNumber(59, 2));
      break;

    case 'p': 
      dumpData();
      break;

    case 't':
      clock_get_time(current_time);
      clock_print_time(current_time);
      break;

    case 'n':
      Serial.print("Total samples: ");
      Serial.println(total_samples);
      break;

    case 'l':
      printSample(current_sample);
      break;

    case 'H':
    default:
      usage();
      break;
    }
  } 
}

static uint8_t tc74_read_byte(uint8_t reg) {
  uint8_t b = 0;
  if (twi.start(TC74_DEV_ID, I2C_WRITE)) {
    twi.write((uint8_t)reg & 0xFF);
    twi.start(TC74_DEV_ID, I2C_READ);
    b = twi.read(true);
    twi.stop();
  } 
  else {
    Serial.println("nack for dev_id / write");
  } 
  return b;  
}

static uint8_t tc74_set_byte(uint8_t reg, uint8_t b) {
  if (twi.start(TC74_DEV_ID, I2C_WRITE)) {
    twi.write((uint8_t)reg & 0xFF);
    twi.write(b);
    twi.stop();
  } 
  else {
    Serial.println("nack for dev_id / write");
  } 
  return b;  
}

#define INTERRUPT_PIN 2
#define INDICATOR_PIN 13

void goToSleep() {
  Serial.print("go to sleep clock control: 0x");
  uint8_t b = ds3231m_get(CONTROL_ADDR);
  Serial.println(b, HEX);
  Serial.print("go to sleep clock status: 0x");
  b = ds3231m_get(STATUS_ADDR);
  Serial.println(b, HEX);

  // tell TC74 to sleep (go to STANDBY mode)
  tc74_set_byte(TC74_CFG_ADDR, 0b10000000);

  // prevent sleep problems
  delay(2);
  Sleep.powerDownAndWakeupExternalEvent(0);
}

void wakeUp() {
  // tell TC74 to wake up (go to NORMAL mode)
  tc74_set_byte(TC74_CFG_ADDR, 0b00000000);

  Serial.print("wake up clock control: 0x");
  uint8_t b = ds3231m_get(CONTROL_ADDR);
  Serial.println(b, HEX);
  Serial.print("wake up clock status: 0x");
  b = ds3231m_get(STATUS_ADDR);
  Serial.println(b, HEX);
  ds3231m_set(STATUS_ADDR, 0b00000000); // reset the alarm flags so the interrupt stops tripping
}

void setup() {
  pinMode(INTERRUPT_PIN, INPUT);   // to get clock alarm interrupt
  digitalWrite(INTERRUPT_PIN, HIGH); // turn on pullup

  pinMode(INDICATOR_PIN, OUTPUT); // to blink LED

  Serial.begin(9600);

  twi.init(true);

  delay(50);

  clock_init();

  i2c_eeprom_init(&twi);
  i2c_eeprom_read_buffer(TOTAL_SAMPLES_ADDRESS, (uint8_t*)(&total_samples), sizeof(total_samples));

  clock_get_time(current_time);

  current_sample.sample      = total_samples++;
  current_sample.time        = current_time;
  current_sample.temperature = 42;

  mode = UNDEFINED;
}

void loop() {
  if (mode == INTERACTIVE || mode == UNDEFINED) {
    processCommands();
  } 
  else if (mode == EMBEDDED) {
    blink();
    blink();
    Serial.println("about to go to sleep at time");
    clock_get_time(current_time);
    clock_print_time(current_time);

    goToSleep();
    wakeUp();

    delay(1000); // keep this in so we have time to read the multimeter!
    Serial.println("just woke up!");
    getSample();
    blink();
    blink();
  }
  if (count_down > 0 && mode == UNDEFINED) {
    count_down--;
    Serial.print("Entering EMBEDDED mode in ");
    Serial.print(count_down, DEC);
    Serial.println(" seconds!");
  } 
  else if (count_down == 0 && mode == UNDEFINED) {
    Serial.println("Entered EMBEDDED mode.");
    Serial.println("Press RESET to get another chance to enter INTERACTIVE mode.");
    mode = EMBEDDED;
  }
  delay(900);
}

void blink() {
  digitalWrite(INDICATOR_PIN, HIGH);
  delay(50);
  digitalWrite(INDICATOR_PIN, LOW);
}  

void writeSample(const data_record_type& s) {
  // compute the offset into the EEPROM for the sample
  uint32_t addr = SAMPLE_DATA_ADDRESS + (sizeof(s) * s.sample);
  i2c_eeprom_write_buffer(addr, (uint8_t*)&s, sizeof(s));
  // save the total number of samples
  i2c_eeprom_write_buffer(TOTAL_SAMPLES_ADDRESS, (uint8_t*)&total_samples, sizeof(total_samples));
}

void getSample() {
  // collect the data we need
  clock_get_time(current_time);
  current_sample.sample      = total_samples++;
  current_sample.time        = current_time;
  current_sample.temperature = getTemp();  

  // save the sample to EEPROM
  writeSample(current_sample);
}

uint8_t getTemp() {
  uint8_t temp = 0;
  temp = tc74_read_byte(TC74_TEMP_ADDR);
  return temp;
}

