# CHRIS — ESP32 buddy (Wokwi prototype)

A **visual prototype** of the physical CHRIS buddy, running in the free
[Wokwi](https://wokwi.com) simulator — **no hardware needed**. It shows the same
5 states as the desktop companion on a small TFT and lets you **Approve/Deny** a
(fake) incoming request with **2 buttons**.

> This is a throwaway prototype in **Arduino C++** just to feel out the UX and
> wiring. The real firmware will be **Rust (`no_std`, esp-hal)** later — this
> is only to play with while the board is on the way.

## What it does
- **idle** (cyan): calm, "watching".
- **alert** (orange): a request arrives showing a fake command (`rm -rf build/`)
  and `GRN=Allow / RED=Deny`.
  - Green button → **approved** (green). Red button → **denied** (coral).
  - No answer in 10s → **denied** (fail-safe), same policy as CHRIS.
- **pull req** (blue): every 4th request is a PR notification.

## Run it (2 minutes, no install)
1. Go to **https://wokwi.com** and create a **New Project → ESP32 → Arduino**.
2. Replace the project's `diagram.json` with the one here.
3. Replace `sketch.ino` with the one here.
4. Add the libraries: open the **Library Manager** (the 📦 icon) and add
   **Adafruit GFX Library** and **Adafruit ILI9341** (or paste `libraries.txt`).
5. Press **▶ Play**. Click the green/red buttons when the orange "APPROVE?"
   screen shows.

> If a wire looks unplugged, Wokwi's pin names can vary slightly by version —
> just drag the wire to the right pin in the editor. The pin map is below.

## Wiring (ESP32 DevKit ↔ ILI9341)
| TFT pin | ESP32 |
|--------|-------|
| VCC / LED | 3V3 |
| GND | GND |
| CS | GPIO5 |
| RST | GPIO4 |
| D/C | GPIO2 |
| MOSI | GPIO23 |
| SCK | GPIO18 |
| MISO | GPIO19 |
| Green button | GPIO32 → GND |
| Red button | GPIO33 → GND |

## Which board to buy (real hardware)
- 🥇 **M5StickC Plus2** — ESP32 + screen + 2 buttons + battery + case, no soldering.
- 🥈 **LilyGO T-Display-S3** — ESP32-S3, bigger 1.9" screen, 2 buttons.
- 🔧 **ESP32-C3 + round GC9A01 + 2 buttons** — cutest, RISC-V (easiest Rust
  toolchain), but needs wiring.

The Wokwi prototype uses a generic ESP32 + ILI9341 because those are the parts
Wokwi ships; the on-device logic (states + 2 buttons) maps directly to any of
the boards above.
