// vim:set ts=2 sw=2 ai et syntax=c:
// Mon Nov  2 13:25:55 EST 2009

/*
 * (c) Copyright 2009 Michael C. Toren <mct@toren.net>
 * Released under the terms of the 2-clause BSD License.  Please contact
 * the author if you have a need for other licensing arrangements.
 */

#include <SoftwareSerial.h>

// Connect pin PIN_TNC_TX to the DB9 transmit pin
// Don't bother connecting PIN_TNC_RX anywhere; we never read.
#define  PIN_TNC_RX  3
#define  PIN_TNC_TX  2

// built-in LED
#define  PIN_LED  13

// KISS constants from http://www.ka9q.net/papers/kiss.html
#define FEND    0xC0  // Frame End
#define FESC    0xDB  // Frame Escape
#define TFEND   0xDC  // Transposed Frame End
#define TFESC   0xDD  // Transposed Frame Escape

char header[] = {
    0x0, // KISS Data on port0
    ('A'<<1), ('P'<<1), ('Z'<<1), ('1'<<1), ('1'<<1), ('1'<<1), ( 0<<1)|0xE0|0, // Receiver
    ('K'<<1), ('J'<<1), ('6'<<1), ('A'<<1), ('O'<<1), ('D'<<1), (11<<1)|0x60|0, // Sender
    ('W'<<1), ('I'<<1), ('D'<<1), ('E'<<1), ('2'<<1), (' '<<1), ( 2<<1)|0x60|1, // Repeater
    0x03, // AX.25 UI frame
    0xF0, // Protocol ID; No layer3 protocol
  };

char aprs[256];

SoftwareSerial tnc =  SoftwareSerial(PIN_TNC_RX, PIN_TNC_TX);

void setup() {
  Serial.begin(9600);
  
  pinMode(PIN_TNC_RX, INPUT);
  pinMode(PIN_TNC_TX, OUTPUT);
  tnc.begin(9600);
  
  pinMode(PIN_LED, OUTPUT);
}

void send_aprs_char(char c) {
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

void send_aprs() {
  tnc.print(FEND, BYTE);

  for (int i = 0; i < sizeof(header); i++)
    send_aprs_char(header[i]);

  for (int i = 0; aprs[i]; i++)
    send_aprs_char(aprs[i]);

  tnc.print(FEND, BYTE);
}

void loop() {

  if (Serial.available() > 0) {
    while (Serial.available() > 0)
      Serial.read();

    Serial.print(" Sending APRS packet on pin ");
    Serial.print(PIN_TNC_TX);
  
    unsigned long time = millis();
    snprintf(aprs, sizeof(aprs), ">Bacchus Test Packet, Arduino Uptime %lu seconds", time/1000);
    digitalWrite(PIN_LED, HIGH);  
    send_aprs();
    digitalWrite(PIN_LED, LOW);

    Serial.print("\r\n");
  }
}
