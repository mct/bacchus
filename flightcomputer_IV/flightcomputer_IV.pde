// vim:set ts=4 sw=4 ai et syntax=c:

#include <SoftwareSerial.h>
#include "gps.h"

// Digital IO pins
#define PIN_TNC_TX       2
#define PIN_TNC_RX       3
#define PIN_BLUE         6
#define PIN_GREEN        8
#define PIN_YELLOW      10
#define PIN_LOGGER_TX   12
#define PIN_LOGGER_RX   13

// Analog IO pins
#define PIN_TEMP_BOARD   0
#define PIN_ACC_X        1
#define PIN_ACC_Y        2
#define PIN_ACC_Z        3
#define PIN_TEMP_INT     4
#define PIN_TEMP_EXT     5

// How often we do things. Time is measured in milliseconds (1000ms == 1 second)
#define TRANSMIT_INTERVAL  (15L*1000L)  // How often we transmit
#define ACC_READ_INTERVAL  ( 1L*1000L)  // How often we read the accelerometer
#define TEMP_READ_INTERVAL ( 1L*1000L)  // How often we read the temperature
#define GPS_HOLD_LOCK      ( 4L*1000L)  // How long to hold a GPS lock for

// KISS constants from http://www.ka9q.net/papers/kiss.html
#define FEND    0xC0  // Frame End
#define FESC    0xDB  // Frame Escape
#define TFEND   0xDC  // Transposed Frame End
#define TFESC   0xDD  // Transposed Frame Escape

char kiss_header[] = {
        0x0, // KISS Data on port0
        ('A'<<1), ('P'<<1), ('Z'<<1), ('1'<<1), ('1'<<1), ('1'<<1), ( 0<<1)|0xE0|0, // Receiver
        ('K'<<1), ('J'<<1), ('6'<<1), ('A'<<1), ('O'<<1), ('D'<<1), (11<<1)|0x60|0, // Sender
        ('W'<<1), ('I'<<1), ('D'<<1), ('E'<<1), ('2'<<1), (' '<<1), ( 2<<1)|0x60|1, // Repeater
        0x03, // AX.25 UI frame
        0xF0, // Protocol ID; No layer3 protocol
    };

unsigned long uptime,         // How long we've been running
              sec, min, hour, // Uptime in hours, minutes, and seconds
              last_transmit,  // Time of last transmission
              last_acc_read,  // Time of last accellerometer reading
              last_temp_read, // Time of last temperature reading
              last_gps_lock;  // Time of the last GPS lock

char upstring[20],            // Buffer to store the uptime as a string
     nmea_buf[256],           // Buffer to store an NMEA string as we're reading it
     nmea_latlong[200],       // Buffer to save the last NMEA string with a lat/long
     buf[256];                // Random buffer for sprintfs

int buf_len,
    nmea_buf_len,
    nmea_latlong_len;

int gps_lock;

SoftwareSerial TNC    = SoftwareSerial(PIN_TNC_RX,    PIN_TNC_TX);
SoftwareSerial Logger = SoftwareSerial(PIN_LOGGER_RX, PIN_LOGGER_TX);

void send_kiss_char(char c) {
    switch (c) {
        case FESC:
            TNC.print(FESC, BYTE);
            TNC.print(TFESC, BYTE);
            break;

        case FEND:
            TNC.print(FESC, BYTE);
            TNC.print(TFEND, BYTE);
            break;

        default:
            TNC.print(c);
    }
}

void send_aprs(char *string, int len) {
    digitalWrite(PIN_BLUE, HIGH);
    TNC.print(FEND, BYTE);

    for (int i = 0; i < sizeof(kiss_header); i++)
        send_kiss_char(kiss_header[i]);

    for (int i = 0; i < len; i++)
        send_kiss_char(string[i]);

    TNC.print(FEND, BYTE);

    // Allow everything to settle again, after our little RF burst
    for (int i = 0; i < 4*1; i++) {
        Serial.print("Sleep... ");
        Logger.print("Sleep... ");
        delay(250);
    }
    Serial.println("");
    Logger.println("");

    digitalWrite(PIN_BLUE, LOW);
}

void setup() {
    Serial.begin(9600);

    pinMode(PIN_TNC_RX, INPUT);
    pinMode(PIN_TNC_TX, OUTPUT);
    TNC.begin(9600);

    pinMode(PIN_LOGGER_RX, INPUT);
    pinMode(PIN_LOGGER_TX, OUTPUT);
    Logger.begin(9600);

    pinMode(PIN_YELLOW, OUTPUT);
    pinMode(PIN_GREEN, OUTPUT);
    pinMode(PIN_BLUE, OUTPUT);

    analogReference(EXTERNAL);

    last_transmit = 0;
    last_acc_read = 0;
    last_temp_read = 0;
    last_gps_lock = 0;
    gps_lock = 0;

    nmea_latlong_len = snprintf(nmea_latlong, sizeof(nmea_latlong), ">No GPS yet\r\n");
    nmea_buf_len = 0;

    // Give everything a chance to settle
    // But while we're waiting for that, no reason we can't blink some LEDs
    for (int i = 0; i < 6; i++) {
        if (0) {
            digitalWrite(PIN_BLUE,   HIGH); delay(250); digitalWrite(PIN_BLUE,   LOW);
            digitalWrite(PIN_GREEN,  HIGH); delay(250); digitalWrite(PIN_GREEN,  LOW);
            digitalWrite(PIN_YELLOW, HIGH); delay(250); digitalWrite(PIN_YELLOW, LOW);
            delay(250);
        } else {
            for (int i = 0; i < 2; i++) {
                digitalWrite(PIN_BLUE,   HIGH);
                digitalWrite(PIN_GREEN,  HIGH);
                digitalWrite(PIN_YELLOW, HIGH);
                delay(250);
                digitalWrite(PIN_BLUE,   LOW);
                digitalWrite(PIN_GREEN,  LOW);
                digitalWrite(PIN_YELLOW, LOW);
                delay(250);
            }
        }
    }

    Serial.println("Startup");
    Logger.println("Startup");
}

static inline void read_gps(void)
{
    if (! (Serial.available() > 0))
        return;

    digitalWrite(PIN_GREEN, HIGH);

    do {
        int c = Serial.read();

        // Special case.  If we see a Control-T, assume it's a command from a
        // human over a serial port asking us to transmit a test packet right
        // now, instead of data coming from the GPS.
        if (c == 'T' - 64) { // Control characters effective subtract 64 from the ASCII value
            buf_len = snprintf(buf, sizeof(buf), ">ProjectBacchus.org Test Packet, Arduino Uptime %s\r\n", upstring);
            Serial.print("Sending APRS Test Packet: ");
            Logger.print("Sending APRS Test Packet: ");
            Serial.print(buf);
            Logger.print(buf);
            send_aprs(buf, buf_len);
            continue;
        }

        if (nmea_buf_len < sizeof(nmea_buf)) {
            if ((c == '\n' || c == '\r') || (32 <= c && c <= 126))
                nmea_buf[nmea_buf_len++] = c;
            else {
                nmea_buf[nmea_buf_len++] = '~';
                Serial.println("Garbage");
                Logger.println("Garbage");
            }
        }

        if (c == '\n') {
            Serial.print(upstring);
            Logger.print(upstring);
            Serial.print(" ");
            Logger.print(" ");

            for (int i = 0; i < nmea_buf_len; i++) {
                Serial.print(nmea_buf[i], BYTE);
                Logger.print(nmea_buf[i], BYTE);
            }

            if (nmea_buf[nmea_buf_len-1] != '\n') {
                Serial.println(" (truncated)");
                Logger.println(" (truncated)");
            }

            // Remember the last GPGGA line
            if (nmea_buf_len >= 8 && nmea_buf_len <= sizeof(nmea_latlong) && strncmp(nmea_buf, "$GPGGA,", 7) == 0) {
                memcpy(nmea_latlong, nmea_buf, nmea_buf_len);
                nmea_latlong_len = nmea_buf_len;

                if (is_gps_lock(nmea_latlong, nmea_latlong_len))
                    last_gps_lock = uptime;
                    gps_lock = 1;
            }

            nmea_buf_len = 0;
        }
    } while (Serial.available() > 0);

    if (!gps_lock)
        digitalWrite(PIN_GREEN, LOW);
}

struct {
    const char *name;
    const int pin;
    int raw;
    float voltage, celsius, fahrenheit;
} temp[] = {
    { "board",PIN_TEMP_BOARD,  0, 0, 0, 0  },
    { "int",  PIN_TEMP_INT,    0, 0, 0, 0  },
    { "ext",  PIN_TEMP_EXT,    0, 0, 0, 0  },
    { NULL,   0,               0, 0, 0, 0  }
};

static inline void read_temp(void)
{
    // http://www.ladyada.net/learn/sensors/tmp36.html
    for (int i = 0; temp[i].name; i++) {
        temp[i].raw = analogRead(temp[i].pin);
        temp[i].voltage = temp[i].raw * 3.3 / 1024;
        temp[i].celsius = (temp[i].voltage - 0.5) * 100;
        temp[i].fahrenheit = temp[i].celsius * 9/5 + 32;
    }

    snprintf(buf, sizeof(buf), "%s Temperature:  %s %dF (%d raw), %s %dF (%d raw), %s %dF (%d raw)\r\n",
        upstring,
        temp[0].name, (int)temp[0].fahrenheit, temp[0].raw,
        temp[1].name, (int)temp[1].fahrenheit, temp[1].raw,
        temp[2].name, (int)temp[2].fahrenheit, temp[2].raw);
    Serial.print(buf);
    Logger.print(buf);
}

struct {
    const char *name;
    const int pin;
    int raw;
    float g;
    int sign;
} accelerometer[] = {
    { "X",  PIN_ACC_X, 0, 0,  1 },
    { "Y",  PIN_ACC_Y, 0, 0, -1 },  // The Y and Z axis are inverted, because the chip
    { "Z",  PIN_ACC_Z, 0, 0, -1 },  //    is mounted upside-down on the breakout board.
    { NULL, 0,         0, 0,  0 }
};

static inline void read_accelerometer(void)
{
    #define V_PER_G 0.600

    for (int i = 0; accelerometer[i].name; i++) {
        accelerometer[i].raw = analogRead(accelerometer[i].pin);
        accelerometer[i].g = (accelerometer[i].raw - 1024/2) / (V_PER_G/3.3*1024);
        accelerometer[i].g *= accelerometer[i].sign;
    }

    Serial.print(upstring);
    Serial.print(" Accelerometer");
    Serial.print(" X=");   Serial.print(accelerometer[0].raw);
    Serial.print(" Y=");   Serial.print(accelerometer[1].raw);
    Serial.print(" Z=");   Serial.print(accelerometer[2].raw);
    Serial.print("   ");
    Serial.print(" X=");   Serial.print  (accelerometer[0].g, 4);
    Serial.print(" Y=");   Serial.print  (accelerometer[1].g, 4);
    Serial.print(" Z=");   Serial.println(accelerometer[2].g, 4);

    Logger.print(upstring);
    Logger.print(" Accelerometer");
    Logger.print(" X=");   Logger.print(accelerometer[0].raw);
    Logger.print(" Y=");   Logger.print(accelerometer[1].raw);
    Logger.print(" Z=");   Logger.print(accelerometer[2].raw);
    Logger.print("   ");
    Logger.print(" X=");   Logger.print  (accelerometer[0].g, 4);
    Logger.print(" Y=");   Logger.print  (accelerometer[1].g, 4);
    Logger.print(" Z=");   Logger.println(accelerometer[2].g, 4);
}

static inline void transmit(void)
{
    static int packet_type;  // Which type of packet to send next

    Serial.print(upstring);
    Logger.print(upstring);
    Serial.print(" ");
    Logger.print(" ");

    switch (packet_type) {
        case 0:
            Serial.print("Sending GPS packet: ");
            Logger.print("Sending GPS packet: ");

            for (int i = 0; i < nmea_latlong_len; i++) {
                Serial.print(nmea_latlong[i], BYTE);
                Logger.print(nmea_latlong[i], BYTE);
            }

            send_aprs(nmea_latlong, nmea_latlong_len);
            break;

        case 1:
            Serial.print("Sending Sensors packet: ");
            Logger.print("Sending Sensors packet: ");

            buf_len = snprintf(buf, sizeof(buf),
                ">ProjectBacchus.org Uptime=%s Temp=%dF,%dF,%dF (%d,%d,%d) Acc=%d,%d,%d\r\n",
                    upstring,
                    (int)temp[0].fahrenheit,
                    (int)temp[1].fahrenheit,
                    (int)temp[2].fahrenheit,
                    temp[0].raw,
                    temp[1].raw,
                    temp[2].raw,
                    accelerometer[0].raw,
                    accelerometer[1].raw,
                    accelerometer[2].raw);

            Serial.print(buf);
            Logger.print(buf);

            send_aprs(buf, buf_len);
            break;

        default:
            Serial.println("I don't know what packet type to send?");
            Logger.println("I don't know what packet type to send?");
    }

    packet_type = (packet_type + 1) % 2;
}

void loop() {
    uptime = millis(); // Overflows every 50 days
    sec  = (uptime / 1000) % 60;
    min  = (uptime / 1000 / 60) % 60;
    hour = (uptime / 1000 / 60 / 60) % 60;

    snprintf(upstring, sizeof(upstring), "%02lu:%02lu:%02lu", hour, min, sec);

    read_gps();

    if (uptime - last_temp_read >= TEMP_READ_INTERVAL) {
        digitalWrite(PIN_YELLOW, HIGH);
        read_temp();
        last_temp_read = uptime;
        digitalWrite(PIN_YELLOW, LOW);
    }

    if (uptime - last_acc_read >= ACC_READ_INTERVAL) {
        read_accelerometer();
        last_acc_read = uptime;
    }

    if (uptime - last_transmit >= TRANSMIT_INTERVAL) {
        transmit();
        last_transmit = uptime;
    }

    if (uptime - last_gps_lock >= GPS_HOLD_LOCK) {
        digitalWrite(PIN_GREEN, LOW);
        gps_lock = 0;
    }
}
