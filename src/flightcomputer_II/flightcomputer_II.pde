// vim:set ts=2 sw=2 ai et syntax=c:

/*
 * (c) Copyright 2009-2010 Michael C. Toren <mct@toren.net>
 * Released under the terms of the 2-clause BSD License.  Please contact
 * the author if you have a need for other licensing arrangements.
 */

#include <SoftwareSerial.h>

// Digital IO pins
#define PIN_TNC_RX      3 // NC
#define PIN_TNC_TX      2

#define PIN_LOGGER_RX   9 // NC
#define PIN_LOGGER_TX   8
#define PIN_LED         13

// Analog IO pins
#define PIN_ACC_Z       0
#define PIN_ACC_Y       1
#define PIN_ACC_X       2

#define PIN_TEMP_EXT    4
#define PIN_TEMP_INT    5

// Time is measured in milliseconds (1000ms = 1 second)
#define TRANSMIT_INTERVAL  (30*1000)  // How often we transmit
#define ACC_READ_INTERVAL  (    500)  // How often we read the accelerometer
#define TEMP_READ_INTERVAL ( 5*1000)  // How often we read the temperature

// KISS constants from http://www.ka9q.net/papers/kiss.html
#define FEND    0xC0  // Frame End
#define FESC    0xDB  // Frame Escape
#define TFEND   0xDC  // Transposed Frame End
#define TFESC   0xDD  // Transposed Frame Escape

char kiss_header[] = {
    0x0,  // Port 0
    ('A'<<1), ('P'<<1), ('Z'<<1), ('B'<<1), ('A'<<1), ('1'<<1),     ( 0<<1)|0xE0|0, // Receiver, APZBA1-0
    ('K'<<1), ('J'<<1), ('6'<<1), ('A'<<1), ('O'<<1), ('D'<<1),     (11<<1)|0x60|0, // Sender,   KJ6AOD-11
    ('W'<<1), ('I'<<1), ('D'<<1), ('E'<<1), ('2'<<1), (' '<<1),     ( 2<<1)|0x60|1, // Repeater, WIDE2-2
    0x03, // AX.25 UI frame
    0xF0, // Protocol ID; No layer3 protocol
  };

unsigned long uptime,         // How long we've been running
              last_transmit,  // Time of last transmission
              last_acc_read,  // Time of last accellerometer reading
              last_temp_read; // Time of last temperature reading

unsigned long hour, min, sec;

char aprs[256],               // Buffer to store text of APRS payload
     nmea_buf[256],           // Buffer to store an NMEA string as we're reading it
     nmea_latlong[200];       // Buffer to save the last NMEA string with a lat/long

int aprs_len,
    nmea_buf_len,
    nmea_latlong_len;

int x, y, z;                   // Most recent accellerometer readings
int temp_ext, temp_int;        // Most recent temperature readings

SoftwareSerial tnc    = SoftwareSerial(PIN_TNC_RX,    PIN_TNC_TX);
SoftwareSerial logger = SoftwareSerial(PIN_LOGGER_RX, PIN_LOGGER_TX);

void send_kiss_char(char c) {
  switch (c) {
    case FESC:
      tnc.print(FESC, BYTE);
      tnc.print(TFESC, BYTE);
      break;

    case FEND:
      tnc.print(FESC, BYTE);
      tnc.print(TFEND, BYTE);
      break;

    default:
      tnc.print(c);
  }
}

void send_aprs(char *string, int len) {
  digitalWrite(PIN_LED, HIGH);  
  tnc.print(FEND, BYTE);

  for (int i = 0; i < sizeof(kiss_header); i++)
    send_kiss_char(kiss_header[i]);

  for (int i = 0; i < len; i++)
    send_kiss_char(string[i]);

  tnc.print(FEND, BYTE);
  digitalWrite(PIN_LED, LOW);
}

void setup() {
  // Output on the serial is used for debugging; you can attach to the FTDI
  // cable and see what the program is doing.  Maybe we'll leave it this way,
  // or maybe we'll move the TNC to the real serial port, rather than using
  // SoftwareSerial.
  //
  // Input on the serial comes from the GPS.  This means that when you want to
  // re-flash the boarduino, you need to disconnect the GPS's transmit pin, or
  // the bootloader will fail to communiate with the PC properly.
  Serial.begin(9600);
  
  // SoftwareSerial output only to the TNC.
  pinMode(PIN_TNC_RX, INPUT);
  pinMode(PIN_TNC_TX, OUTPUT);
  tnc.begin(9600);
  
  // SoftwareSerial output only to the logging module
  pinMode(PIN_LOGGER_RX, INPUT);
  pinMode(PIN_LOGGER_TX, OUTPUT);
  logger.begin(9600);
  
  // Built-in boarduino LED
  pinMode(PIN_LED, OUTPUT);

  // Analog reference is connected to the 3.3v reference pin of the accelerometer
  analogReference(EXTERNAL);

  last_transmit = 0;
  last_acc_read = 0;
  last_temp_read = 0;

  x = y = z = 0;
  temp_ext = temp_int = 0;

  nmea_latlong_len = snprintf(nmea_latlong, sizeof(nmea_latlong), ">No GPS yet\r\n");
  nmea_buf_len = 0;

  Serial.println("Startup"); delay(250);
  logger.println("Startup");
  aprs_len = snprintf(aprs, sizeof(aprs), ">ProjectBacchus.org Startup\r\n");
  send_aprs(aprs, aprs_len);
}

void loop() {
  uptime = millis(); // Overflows every 50 days

  // Read as fast as we can from the receive serial buffer.
  // TODO: Perhaps increase the Arduino receive serial buffer size.
  while (Serial.available() > 0) {
    int c = Serial.read();

    if (nmea_buf_len < sizeof(nmea_buf))
      nmea_buf[nmea_buf_len++] = c;

    if (c == '\n') {
      Serial.print("GPS: ");

      logger.print(uptime);
      logger.print(" ");

      for (int i = 0; i < nmea_buf_len; i++) {
        Serial.print(nmea_buf[i]);
        logger.print(nmea_buf[i]);
      }

      if (nmea_buf[nmea_buf_len-1] != '\n') {
        Serial.println(" (truncated)");
        logger.println(" (truncated)");
      }

      // Remember the last GPGGA line.  Or do we want GPRMC?
      if (nmea_buf_len >= 8 && nmea_buf_len <= sizeof(nmea_latlong) && strncmp(nmea_buf, "$GPGGA,", 7) == 0) {
        Serial.println("New GPS location string");
        memcpy(nmea_latlong, nmea_buf, nmea_buf_len);
        nmea_latlong_len = nmea_buf_len;
      }

      nmea_buf_len = 0;
    }
  }

  if (uptime - last_temp_read >= TEMP_READ_INTERVAL) {
    temp_ext = analogRead(PIN_TEMP_EXT); // delay(10);
    temp_int = analogRead(PIN_TEMP_INT); // delay(10);

    Serial.print("temp_ext=");  Serial.print(temp_ext);
    Serial.print(" temp_int="); Serial.println(temp_int);

    logger.print(uptime);
    logger.print(" temp_ext="); logger.print(temp_ext);
    logger.print(" temp_int="); logger.println(temp_int);

    last_temp_read = uptime;
  }

  if (uptime - last_acc_read >= ACC_READ_INTERVAL) {
    x = analogRead(PIN_ACC_X); // delay(10);
    y = analogRead(PIN_ACC_Y); // delay(10);
    z = analogRead(PIN_ACC_Z); // delay(10);

    Serial.print("X=");  Serial.print(x);
    Serial.print(" Y="); Serial.print(y);
    Serial.print(" Z="); Serial.println(z);

    logger.print(uptime);
    logger.print(" X="); logger.print(x);
    logger.print(" Y="); logger.print(y);
    logger.print(" Z="); logger.println(z);

    last_acc_read = uptime;
  }

  if (uptime - last_transmit >= TRANSMIT_INTERVAL) {
    Serial.println("Sending KISS");

    send_aprs(nmea_latlong, nmea_latlong_len);

    // Is this delay necessary because of the TNC?
    // Or is it perhaps working fine, but multimon can't decode it properly?
    //
    // Another idea to test later:  Modify the send_aprs() function to support
    // using the first frame's trailing FEND as the leading FEND for the second
    // frame, rather than sending two FEND's back to back.
    delay(2000);

    sec =  (uptime / 1000) % 60;
    min =  (uptime / 1000 / 60) % 60;
    hour = (uptime / 1000 / 60 / 60) % 60;

    aprs_len = snprintf(aprs, sizeof(aprs),
        ">ProjectBacchus.org Up=%02lu:%02lu:%02lu X=%d Y=%d Z=%d TI=%d TE=%d\r\n",
            hour, min, sec,
            x, y, z,
            temp_int, temp_ext);
    send_aprs(aprs, aprs_len);

    last_transmit = uptime;
  }
}
