// CHRIS — ESP32 buddy prototype (Wokwi simulation)
//
// A throwaway VISUAL prototype to feel out the desk-buddy UX before the real
// Rust (no_std) firmware. It shows the same 5 states as the desktop companion
// on a small TFT and lets you Approve/Deny an incoming request with 2 buttons.
//
// Flow: idle -> (a fake request arrives) alert -> press GREEN=Allow / RED=Deny
//       -> approved/denied -> back to idle. No answer in time = Deny (fail-safe),
//       just like CHRIS. Occasionally a blue "PR" notification pops up.
//
// Hardware in the Wokwi diagram: ESP32 DevKit + ILI9341 TFT + 2 pushbuttons.

#include <Adafruit_GFX.h>
#include <Adafruit_ILI9341.h>

// --- pins (match diagram.json) ---
#define TFT_CS    5
#define TFT_DC    2
#define TFT_RST   4
#define BTN_ALLOW 32   // green button
#define BTN_DENY  33   // red button

Adafruit_ILI9341 tft = Adafruit_ILI9341(TFT_CS, TFT_DC, TFT_RST);

// --- CHRIS state colors (same hex as the desktop app) ---
uint16_t C_BG, C_IDLE, C_ALERT, C_APPR, C_DENY, C_PR, C_EYE, C_TXT;

enum State { IDLE, ALERT, APPROVED, DENIED, PR };
State state = IDLE;
unsigned long tEnter = 0;                 // millis when we entered the state
const char* PENDING = "rm -rf build/";    // the fake command being approved
int idleCount = 0;                        // to sprinkle in a PR now and then

// moods for the mouth
enum Mood { NEUTRAL, MOUTH_O, SMILE, FROWN };

void setState(State s) { state = s; tEnter = millis(); drawState(); }

void setup() {
  pinMode(BTN_ALLOW, INPUT_PULLUP);
  pinMode(BTN_DENY, INPUT_PULLUP);

  tft.begin();
  tft.setRotation(0);           // 240x320 portrait

  C_BG    = tft.color565(10, 12, 18);
  C_IDLE  = tft.color565(52, 205, 214);   // cyan
  C_ALERT = tft.color565(255, 159, 67);   // orange
  C_APPR  = tft.color565(46, 204, 113);   // green
  C_DENY  = tft.color565(255, 107, 107);  // coral
  C_PR    = tft.color565(83, 155, 245);   // blue
  C_EYE   = tft.color565(8, 24, 30);
  C_TXT   = ILI9341_WHITE;

  setState(IDLE);
}

void loop() {
  bool allow = digitalRead(BTN_ALLOW) == LOW;
  bool deny  = digitalRead(BTN_DENY) == LOW;
  unsigned long elapsed = millis() - tEnter;

  switch (state) {
    case IDLE:
      // after a few seconds, a request "arrives" (every 4th one is a PR)
      if (elapsed > 4000) {
        idleCount++;
        if (idleCount % 4 == 0) setState(PR);
        else setState(ALERT);
      }
      break;

    case ALERT:
      if (allow)      setState(APPROVED);
      else if (deny)  setState(DENIED);
      else if (elapsed > 10000) setState(DENIED);   // timeout = Deny (fail-safe)
      break;

    case PR:
      // a PR notification: acknowledge with either button, or auto-dismiss
      if (allow || deny || elapsed > 4000) setState(IDLE);
      break;

    case APPROVED:
    case DENIED:
      if (elapsed > 1800) setState(IDLE);
      break;
  }
  delay(20);   // simple debounce / pacing
}

// ---- drawing ----
void drawState() {
  switch (state) {
    case IDLE:     drawFace(C_IDLE,  NEUTRAL, "",  "idle",     "watching"); break;
    case ALERT:    drawFace(C_ALERT, MOUTH_O, "!", "APPROVE?", PENDING);    break;
    case APPROVED: drawFace(C_APPR,  SMILE,   "",  "approved", "");         break;
    case DENIED:   drawFace(C_DENY,  FROWN,   "",  "denied",   "");         break;
    case PR:       drawFace(C_PR,    SMILE,   "?", "pull req", "review me");break;
  }
}

// Draws the little CHRIS creature + labels for the current state.
void drawFace(uint16_t color, Mood mood, const char* emote,
              const char* label, const char* sub) {
  tft.fillScreen(C_BG);

  // body
  tft.fillRoundRect(40, 60, 160, 150, 30, color);

  // eyes
  tft.fillCircle(95, 130, 11, C_EYE);
  tft.fillCircle(150, 130, 11, C_EYE);

  // mouth
  int mx = 122, my = 172;
  switch (mood) {
    case NEUTRAL: tft.drawFastHLine(mx - 18, my, 36, C_EYE); break;
    case MOUTH_O: tft.fillCircle(mx, my, 8, C_EYE); break;
    case SMILE:   // upward "V" (3 segments)
      tft.drawLine(mx - 20, my - 4, mx, my + 10, C_EYE);
      tft.drawLine(mx, my + 10, mx + 20, my - 4, C_EYE);
      break;
    case FROWN:   // downward
      tft.drawLine(mx - 20, my + 8, mx, my - 6, C_EYE);
      tft.drawLine(mx, my - 6, mx + 20, my + 8, C_EYE);
      break;
  }

  // emote (top-right), in the state color
  if (emote[0]) {
    tft.setTextColor(color);
    tft.setTextSize(5);
    tft.setCursor(196, 20);
    tft.print(emote);
  }

  // state label (big, centered-ish, bottom)
  tft.setTextColor(C_TXT);
  tft.setTextSize(3);
  tft.setCursor(centerX(label, 3), 232);
  tft.print(label);

  // sub line (the command / hint)
  if (sub[0]) {
    tft.setTextColor(color);
    tft.setTextSize(2);
    tft.setCursor(centerX(sub, 2), 268);
    tft.print(sub);
  }

  // button hints only while a request is pending
  if (state == ALERT) {
    tft.setTextSize(2);
    tft.setTextColor(C_APPR); tft.setCursor(14, 300);  tft.print("GRN=Allow");
    tft.setTextColor(C_DENY); tft.setCursor(150, 300); tft.print("RED=Deny");
  }
}

// rough horizontal centering for the default 6px-wide font
int centerX(const char* s, int size) {
  int w = strlen(s) * 6 * size;
  int x = (240 - w) / 2;
  return x < 2 ? 2 : x;
}
