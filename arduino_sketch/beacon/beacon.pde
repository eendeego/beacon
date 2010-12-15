/**
 * For assembly and build intructions see the README file
 */

#include "tlc_config.h"
#include "Tlc5940.h"

#define ENABLE_ETHERNET

#ifdef ENABLE_ETHERNET

#include <SPI.h>
#include <Client.h>
#include <Ethernet.h>
#include <Server.h>

#include "ipconfig.h"

#endif

#define BAR_COUNT 4

#define RED   0
#define GREEN 1
#define BLUE  2

class Timer {
  protected:
    uint32_t global_clock_start;
  public:
    Timer() {
    }

    void start(uint32_t clock) {
      global_clock_start = clock;
    }

    void start() {
      start(millis());
    }

    uint32_t elapsed_time(uint32_t clock) {
      if(clock >= global_clock_start)
        return clock - global_clock_start;
      else
        return clock - ((int32_t) global_clock_start);
    }

    uint32_t elapsed_time() {
      return elapsed_time(millis());
    }
};

typedef void (*updater)(struct rgb_data*, uint32_t);

#define MODE_FIXED 0
#define MODE_ALERT 1
#define MODE_PULSE 2
#define MODE_WAVE  3
#define MODE_TEST  4

typedef struct rgb_data {
  uint8_t  rgb_num;
  uint16_t *rgb_addr;

  uint16_t rgb[3];

  int16_t h;
  float   s;
  float   l;

  int16_t start_h;
  int16_t target_h;

  Timer hue_timer;

  uint8_t test_alone;

  uint8_t mode_num;
  updater update;
};

struct rgb_data bars[BAR_COUNT];

uint16_t hue_speed = 40;
#define THETA -64

unsigned int rho    = 0;

uint16_t barColors[] =
{
  0, 0, 0,
  0, 0, 0,
  0, 0, 0,
  0, 0, 0
};

#define BUFFER_SIZE 80
char input_buffer[BUFFER_SIZE+1];
int input_pos = 0;
uint8_t parse_pos, cmd_start;

const char STR_UPDATE[] = "update";

const char STR_BORKED[] = "borked";

// This table was taken from http://www.arduino.cc/playground/Main/PWMallPins
const uint8_t sinewave[] = // maps 0->0x3f to 0x80 * (1 + sin(0->pi/2))
{
  0x80,0x83,0x86,0x89,0x8c,0x8f,0x92,0x95,0x98,0x9c,0x9f,0xa2,0xa5,0xa8,0xab,0xae,
  0xb0,0xb3,0xb6,0xb9,0xbc,0xbf,0xc1,0xc4,0xc7,0xc9,0xcc,0xce,0xd1,0xd3,0xd5,0xd8,

  0xda,0xdc,0xde,0xe0,0xe2,0xe4,0xe6,0xe8,0xea,0xec,0xed,0xef,0xf0,0xf2,0xf3,0xf5,
  0xf6,0xf7,0xf8,0xf9,0xfa,0xfb,0xfc,0xfc,0xfd,0xfe,0xfe,0xff,0xff,0xff,0xff,0xff
};

Timer heartbeat_timer;
uint32_t heartbeat_time = 0;
char heartbeat_buffer[BUFFER_SIZE+1];
int heartbeat_alert_triggered = 0;

#ifdef ENABLE_ETHERNET

byte mac[]     = MAC_ADDRESS;
byte ip[]      = IP_ADDRESS;

Server server(80);

const char HTTP_RESPONSE_HEADER[] =
  "HTTP/1.1 200 OK\r\n"
  "Server: Arduino\r\n"
  "Content-Type: text/plain; charset=UTF-8\r\n"
  "Connection: close\r\n"
  "\r\n";

#endif

// ************************************************************************

Print *printer = &Serial;

#ifdef ENABLE_ETHERNET

#define mprint(...)   printer->print(__VA_ARGS__)
#define mprintln(...) printer->println(__VA_ARGS__)

#else

#define mprint(...)   Serial.print(__VA_ARGS__)
#define mprintln(...) Serial.println(__VA_ARGS__)

#endif
// ************************************************************************

// wave(time) = 0x80 * (1 + sin(time * pi/2 / 0x3f))
uint8_t wave(uint8_t time) {
  if(time < 0x40) return  sinewave[time];
  if(time < 0x80) return  sinewave[0x7f - time];
  if(time < 0xc0) return ~sinewave[time & 0x7f];
                  return ~sinewave[0x7f - (time & 0x7f)];
}

// http://en.wikipedia.org/wiki/HSL_and_HSV#From_HSL
void hsl2rgb(uint16_t h, float s, float l, uint16_t *result) {
  if(s==0) {
    result[0] = result[1] = result[2] = (uint8_t) (255 * l);
    return;
  }

  float q = l < .5 ? (l * (1.0 + s)) : (l + s - (l * s));
  float p = 2 * l - q;

  float hsl_t[] = { 0.0, 0.0, 0.0 };
  hsl_t[0] = h + 120;
  hsl_t[1] = h;
  hsl_t[2] = h - 120;
  if(hsl_t[0] >= 360) hsl_t[0] -= 360;
  if(hsl_t[2] < 0) hsl_t[2] += 360;

  for(int j=2;j>=0; j--) {
    if(hsl_t[j] < 60) {
      result[j] = (uint8_t) (255.0 * (p + ((q-p) * hsl_t[j] / 60.0)));
    } 
    else if(hsl_t[j] < 180) {
      result[j] = (uint8_t) (255.0 * q);
    } 
    else if(hsl_t[j] < 240) {
      result[j] = (uint8_t) (255.0 * (p + ((q-p) * (240 - hsl_t[j]) / 60.0)));
    } 
    else {
      result[j] = (uint8_t) (255.0 * p);
    }
  }
}

void set_raw_bar_color(uint16_t *bar, uint16_t r, uint16_t g, uint16_t b) {
  bar[RED  ] = r;
  bar[GREEN] = g;
  bar[BLUE ] = b;
}

void dump_colors(uint16_t *bar) {
  mprint("rgb(");
  mprint(bar[RED  ], DEC);
  mprint(',');
  mprint(bar[GREEN], DEC);
  mprint(',');
  mprint(bar[BLUE ], DEC);
  mprint(')');
  mprintln();
}

void set_all(uint16_t value) {
  for(int i=11; i>=0; i--)
    Tlc.set(i, value);
}

void reset_colors(uint16_t r, uint16_t g, uint16_t b) {
  uint16_t *pbar = barColors;
  for(int i=0; i<BAR_COUNT; i++, pbar+=3)
    set_raw_bar_color(pbar, r, g, b);
}

void set_color(struct rgb_data *rgb, uint16_t r, uint16_t g, uint16_t b) {
  rgb->rgb[RED  ] = r;
  rgb->rgb[GREEN] = g;
  rgb->rgb[BLUE ] = b;
}

void set_color(struct rgb_data *rgb, uint16_t *new_rgb) {
  rgb->rgb[RED  ] = new_rgb[RED  ];
  rgb->rgb[GREEN] = new_rgb[GREEN];
  rgb->rgb[BLUE ] = new_rgb[BLUE ];
}

void init_color(struct rgb_data *rgb, uint16_t r, uint16_t g, uint16_t b) {
  rgb->s = 1.0;
  rgb->l = 0.5;
  rgb->h = 0;
  rgb->target_h = 0;
  rgb->rgb[RED  ] = r;
  rgb->rgb[GREEN] = g;
  rgb->rgb[BLUE ] = b;
}

void set_h(struct rgb_data *rgb, uint16_t new_h) {
  rgb->start_h = rgb->target_h = rgb->h = new_h;
}

void set_target_h(struct rgb_data *rgb, uint16_t new_h, uint32_t clock) {
  /**
  mprint("setting target_h: ");
  mprint(rgb->rgb_num, DEC);
  mprint(',');
  mprint(rgb->h, DEC);
  mprint(',');
  mprint(new_h, DEC);
  mprintln();
  **/

  rgb->start_h  = rgb->h;
  rgb->target_h = new_h;

  if(rgb->target_h - rgb->h > 180)
    rgb->start_h += 360;
  else
  if(rgb->h - rgb->target_h > 180)
    rgb->start_h -= 360;

  rgb->hue_timer.start(clock);
}

void animate_hue(struct rgb_data *rgb, uint32_t clock) {
  if(rgb->h == rgb->target_h)
    return;

  int16_t dist = abs(rgb->target_h - rgb->start_h);
  int8_t  dir = rgb->target_h > rgb->start_h ? +1 : -1;

  int16_t delta = rgb->hue_timer.elapsed_time(clock) / hue_speed;
  if(delta > dist)
    delta = dist;

  int16_t h = rgb->start_h + delta * dir;

  if(h > 360)
    h -= 360;
  else if(h < 0)
    h += 360;

  rgb->h = h;

  hsl2rgb(rgb->h, rgb->s, rgb->l, rgb->rgb);
  rgb->rgb[RED  ] = map(rgb->rgb[RED  ],0,255,0,4095);
  rgb->rgb[GREEN] = map(rgb->rgb[GREEN],0,255,0,4095);
  rgb->rgb[BLUE ] = map(rgb->rgb[BLUE ],0,255,0,4095);
}

void init_rgb(struct rgb_data *rgb, uint8_t num) {
  rgb->rgb_num = num;
  rgb->rgb_addr = &barColors[num*3];

  init_color(rgb, 4095, 0, 0);

  rgb->mode_num = MODE_TEST;
  rgb->update   = &test_updater;
}

void set_mode(struct rgb_data *rgb, uint8_t mode) {
  rgb->mode_num = mode;
  switch(mode) {
    case MODE_FIXED:
      rgb->update = &fixed_updater;
      break;
    case MODE_ALERT:
      rgb->update = &alert_updater;
      break;
    case MODE_PULSE:
      rgb->update = &pulse_updater;
      break;
    case MODE_WAVE:
      rgb->update = &wave_updater;
      break;
    case MODE_TEST:
      rgb->update = &test_updater;
      break;
  }
}

void fixed_updater(struct rgb_data *rgb, uint32_t clock) {
  animate_hue(rgb, clock);

  set_raw_bar_color(rgb->rgb_addr,
                    rgb->rgb[RED  ],
                    rgb->rgb[GREEN],
                    rgb->rgb[BLUE ]);
}

void alert_updater(struct rgb_data *rgb, uint32_t clock) {
  animate_hue(rgb, clock);

  if((clock / 500) & 0x01)
    set_raw_bar_color(rgb->rgb_addr, 0, 0, 0);
  else
    set_raw_bar_color(rgb->rgb_addr,
                      rgb->rgb[RED],
                      rgb->rgb[GREEN],
                      rgb->rgb[BLUE]);
}

void pulse_updater(struct rgb_data *rgb, uint32_t clock) {
  animate_hue(rgb, clock);

  uint32_t sin = wave(rho);

  set_raw_bar_color(rgb->rgb_addr,
                    (rgb->rgb[RED  ] * sin) / 255,
                    (rgb->rgb[GREEN] * sin) / 255,
                    (rgb->rgb[BLUE ] * sin) / 255);
}

void wave_updater(struct rgb_data *rgb, uint32_t clock) {
  animate_hue(rgb, clock);

  // This is actually: wave((rho + THETA*rgb->rgb_num) & 0xff)
  uint32_t sin = wave(rho + THETA*rgb->rgb_num);

  set_raw_bar_color(rgb->rgb_addr,
                    (rgb->rgb[RED  ] * sin) / 255,
                    (rgb->rgb[GREEN] * sin) / 255,
                    (rgb->rgb[BLUE ] * sin) / 255);
}

void test_updater(struct rgb_data *rgb, uint32_t clock) {
  uint32_t c_num    = (clock / 500) % (rgb->test_alone ? 3 : BAR_COUNT * 3);
  uint32_t base_num = rgb->rgb_num * 3;

  set_raw_bar_color(rgb->rgb_addr,
                    c_num == base_num     ? 4095 : 0,
                    c_num == base_num + 1 ? 4095 : 0,
                    c_num == base_num + 2 ? 4095 : 0);
}

void set_color(uint8_t bm, uint16_t r, uint16_t g, uint16_t b) {
  for(int i=0; i<BAR_COUNT; i++) {
    if(bm & (1 << i))
      set_color(&bars[i], r, g, b);
  }
}

void set_h(uint8_t bm, uint16_t h) {
  for(int i=0; i<BAR_COUNT; i++) {
    if(bm & (1 << i))
      set_h(&bars[i], h);
  }
}

void set_target_h(uint8_t bm, uint16_t h, uint32_t clock) {
  for(int i=0; i<BAR_COUNT; i++) {
    if(bm & (1 << i))
      set_target_h(&bars[i], h, clock);
  }
}

void set_test_alone(uint8_t bm, uint8_t ta) {
  for(int i=0; i<BAR_COUNT; i++) {
    if(bm & (1 << i))
      bars[i].test_alone = ta;
  }
}

void set_mode(uint8_t bm, uint8_t mode) {
  for(int i=0; i<BAR_COUNT; i++) {
    if(bm & (1 << i))
      set_mode(&bars[i], mode);
  }
}

int parse_num() {
  int result = 0;
  for(; input_buffer[parse_pos] &&
        input_buffer[parse_pos]>='0' &&
        input_buffer[parse_pos]<='9'; parse_pos++) {
      result = (result * 10) + (input_buffer[parse_pos] - '0');
  }
  return result;
}

int print_borked() {
  mprintln(STR_BORKED);
}

int print_command() {
  for(uint8_t i=cmd_start; i<parse_pos; i++) {
    mprint(input_buffer[i]);
  }
  mprintln();
}

inline void execute() {
  //mprintln("execute");

  uint8_t  bm  = B1111;
  uint32_t now = millis();
  uint16_t base[]  = {0,0,0};
  int16_t target_h, h, hb, len;
  float s, l;

  parse_pos = 0;
  while(input_buffer[parse_pos]) {
    uint8_t immediate = false;
    cmd_start = parse_pos;

    if(input_buffer[parse_pos] == 'h') {
      if(input_buffer[parse_pos+1] == 's' && input_buffer[parse_pos+2] == 'l' && input_buffer[parse_pos+3] == '(') {
        parse_pos+=4;
        h = target_h = parse_num() % 360;
        if(!input_buffer[parse_pos++]) {
          print_borked();
          return;
        }
        s = parse_num() / 1000.0f;
        if(!input_buffer[parse_pos++]) {
          print_borked();
          return;
        }
        if(s > 1.0f)
          s = 1.0f;
        l = parse_num() / 1000.0f;
        parse_pos++;
        if(l > 1.0f)
          l = 1.0f;

        hsl2rgb(h, s, l, base);

        print_command();

        set_color(bm, base[RED], base[GREEN], base[BLUE]);
      }
      else if(input_buffer[parse_pos+1] == 'b' && input_buffer[parse_pos+2] == '(') {
        parse_pos+=3;
        hb = parse_num();
        if(!input_buffer[parse_pos++]) {
          print_borked();
          return;
        }

        if(input_buffer[parse_pos++] != '"') {
          print_borked();
          return;
        }

        for(len=0; parse_pos+len<BUFFER_SIZE && input_buffer[parse_pos+len] != '"'; len++) ;

        if(parse_pos+len >= BUFFER_SIZE) {
          print_borked();
          return;
        }

        if(input_buffer[parse_pos+len+1] != ')') {
          print_borked();
          return;
        }

        heartbeat_time = hb;
        heartbeat_time *= 1000;
        memcpy(&heartbeat_buffer, &input_buffer[parse_pos], len);
        heartbeat_buffer[len] = 0;
        parse_pos += len + 2;

        print_command();
      }
      else if(input_buffer[parse_pos+1] == '(') {
        parse_pos+=2;
        uint16_t th = parse_num() % 360;
        parse_pos++;
        print_command();

        set_target_h(bm, th, now);
      }
    }
    else if(input_buffer[parse_pos] == 'r') {
      if(input_buffer[parse_pos+1] == 'g' && input_buffer[parse_pos+2] == 'b' && input_buffer[parse_pos+3] == '(') {
        parse_pos+=4;
        base[RED] = parse_num() % 256;
        if(!input_buffer[parse_pos++]) {
          print_borked();
          return;
        }
        base[GREEN] = parse_num() % 256;
        if(!input_buffer[parse_pos++]) {
          print_borked();
          return;
        }
        base[BLUE] = parse_num() % 256;
        parse_pos++;

        print_command();

        set_color(bm,
                  map(base[RED  ],0,255,0,4095),
                  map(base[GREEN],0,255,0,4095),
                  map(base[BLUE ],0,255,0,4095));
      }
      else {
        //assert input_buffer[parse_pos++] in ('.', 0)
        parse_pos++;
        if(input_buffer[parse_pos] == '!') {
          immediate = true;
          parse_pos++;
        }

        print_command();

        if(immediate) {
          set_h(bm, 0);
          set_color(bm, 4095, 0, 0);
        }
        else {
          set_target_h(bm, 0, now);
        }
      }
    }
    else if(input_buffer[parse_pos] == 'g') {
      parse_pos++;
      if(input_buffer[parse_pos] == '!') {
        immediate = true;
        parse_pos++;
      }
      print_command();

      if(immediate) {
        set_h(bm, 120);
        set_color(bm, 0, 4095, 0);
      }
      else {
        set_target_h(bm, 120, now);
      }
    } 
    else if(input_buffer[parse_pos] == 'b') {
      parse_pos++;
      if(input_buffer[parse_pos] == '(') {
        parse_pos++;
        int bn = parse_num();
        bm = 1 << bn;
        //assert input_buffer[parse_pos] == ')'
        parse_pos++;

        print_command();
      }
      else if(input_buffer[parse_pos] == 'm' && input_buffer[parse_pos+1] == '(') {
        parse_pos+=2;
        // defining bar bit mask, not to confuse with bat mask
        bm = parse_num();
        //assert input_buffer[parse_pos] == ')'
        parse_pos++;

        print_command();
      }
      else {
        if(input_buffer[parse_pos] == '!') {
          immediate = true;
          parse_pos++;
        }
        //assert input_buffer[parse_pos++] in ('.', 0)

        if(immediate) {
          set_h(bm, 240);
          set_color(bm, 0, 0, 4095);
        }
        else {
          set_target_h(bm, 240, now);
        }

        print_command();
      }
    }
    else if(input_buffer[parse_pos] == 'f') {
      parse_pos++;

      print_command();
      set_mode(bm, MODE_FIXED);
    }
    else if(input_buffer[parse_pos] == 'a') {
      parse_pos++;

      print_command();
      set_mode(bm, MODE_ALERT);
    }
    else if(input_buffer[parse_pos] == 'p') {
      parse_pos++;

      print_command();
      set_mode(bm, MODE_PULSE);
    }
    else if(input_buffer[parse_pos] == 'w') {
      parse_pos++;

      print_command();
      set_mode(bm, MODE_WAVE);
    }
    else if(input_buffer[parse_pos] == 't') {
      parse_pos++;

      if(input_buffer[parse_pos] == 'a') {
        parse_pos++;
        uint8_t ta = true;

        if(input_buffer[parse_pos] == '!') {
          parse_pos++;
          ta = false;
        }

        print_command();
        set_test_alone(bm, ta);
      }
      else {
        print_command();
        set_mode(bm, MODE_TEST);
      }
    }
    else {
      print_borked();
      mprintln(input_buffer);
      for(int i=0; i<parse_pos; i++) {
        mprint(' ');
      }
      mprint('^');
      mprint(' ');
      mprint(parse_pos, DEC);
      mprint(' ');
      mprint(input_buffer[parse_pos], DEC);
      mprint(' ');
      mprint(input_buffer[parse_pos], HEX);
      mprintln();
      return;
    }

    if(input_buffer[parse_pos] == '.')
      parse_pos++;
  }
}

inline void heartbeat() {
  heartbeat_timer.start();
  heartbeat_alert_triggered = 0;
}

inline void check_heartbeat() {
  if(heartbeat_time && (heartbeat_time < heartbeat_timer.elapsed_time()) && !heartbeat_alert_triggered) {
    // This will take longer than a strncpy, but will shorten the total code size
    memcpy(&input_buffer, &heartbeat_buffer, BUFFER_SIZE);
    // Send command output to serial port even if there's nothing there, otherwise
    // crash trying to send to a closed socket
    printer = &Serial;
    execute();
    input_pos = 0;
    heartbeat_alert_triggered = 1;
  }
}

int handle_input(byte data) {
  if(data == ';') {
    input_buffer[input_pos] = 0;
    execute();
    heartbeat();
    input_pos = 0;
  }
  else {
    if(input_pos < BUFFER_SIZE) {
      if(input_pos != 0 || !(data == '\n' || data == '\r'))
        input_buffer[input_pos++] = data;
    }
  }
}

#ifdef ENABLE_ETHERNET
void handle_network_input() {
  Client client = server.available();
  printer = &client;

  if(client) {
    boolean current_line_is_blank = true;
    boolean skipped_headers = false;

    while(client.connected()) {
      if(client.available()) {
        char c = client.read();
        //client.print(c);
        //mprint(c);

        if (skipped_headers) {
          handle_input(c);
        } else
        if (c == '\n' && current_line_is_blank) {
          client.print(HTTP_RESPONSE_HEADER);

          // Without this delay clients that send requests in separate packets
          // won't work.
          delay(1);

          skipped_headers = true;
        } else {
          if (c == '\n') {
            // we're starting a new line
            current_line_is_blank = true;
          } else
          if (c != '\r') {
            // we've gotten a character on the current line
            current_line_is_blank = false;
          }
        }
      } else {
        break;
      }
    }
    //mprintln("It's gone!");
    //delay(1);
    client.stop();
  }
}
#endif

void handle_serial_input() {
  if(Serial.available()) {
    printer = &Serial;
    handle_input(Serial.read());
  }
}

void setup() {
  heartbeat_timer.start();

  Serial.begin(9600);
#ifdef ENABLE_ETHERNET
  Ethernet.begin(mac, ip);
  server.begin();
#endif

  Tlc.init();
  for(uint8_t i=0; i<BAR_COUNT; i++)
    init_rgb(&bars[i], i);
}

void loop() {
#ifdef ENABLE_ETHERNET
  handle_network_input();
#endif
  handle_serial_input();

  check_heartbeat();

  uint32_t now = millis();
  rho = (now / 20) % 256;
  for(int i=0; i<BAR_COUNT; i++)
    bars[i].update(&bars[i], now);

  uint16_t *pb = barColors;
  for(int i=0; i<12; i++, pb++)
    Tlc.set(i, *pb);
  Tlc.update();
}
