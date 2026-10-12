# Lily component list — RGB and white-light versions

Checked against the project files and manufacturer documentation on 12 October 2026.

Both versions include audio. This list assumes USB/5 V power and ten individual LEDs, matching the cloud/bear enclosure concept. Electrical compatibility is supported by the documentation; assembly, brightness, sound quality and physical fit still need a prototype check.

## Shared components — per device

| Qty | Component | Specification / purpose |
|---|---|---|
| 1 | ESP32-S3 development board — already owned | Check the module marking. Recommended: ESP32-S3-WROOM-1-N16R8 on a suitable development board, with 16 MB flash and 8 MB PSRAM. The firmware currently specifies 16 MB flash. Check and enable the correct PSRAM configuration for the audio build. |
| 1 | MAX98357A I2S amplifier breakout | Mono audio; power from 5 V. Accepts the ESP32's 3.3 V I2S signals directly. Example: Adafruit product 3006. |
| 1 | Moving-coil speaker | 4 ohm, at least 3 W; recommended example: Adafruit 3968, 40 mm diameter, 4 ohm, 5 W. The higher speaker rating does not increase amplifier output. |
| 1 | Regulated 5 V, 3 A power supply | Recommended capacity with margin for Wi-Fi, lighting and audio. Supply capacity is not forced current consumption. |
| 1 | USB power/programming cable | Connector must match the existing board; use a data-capable cable for programming. |
| 1 set | Power distribution, insulated wire, connectors, heat-shrink and small prototype PCB | Feed the amplifier and lights directly from the 5 V distribution point; check the board's power-input rating and wiring capacity. All circuit grounds must be common. |

The MAX98357A drives 4-ohm speakers and accepts 3.3 V logic while powered at 5 V. Its approximately 3 W headline output is at high distortion; clean output is lower. Connect the speaker between amplifier SPK+ and SPK−; neither speaker terminal goes to ground. See [amplifier specifications](https://www.adafruit.com/product/3006), [wiring/output specifications](https://learn.adafruit.com/adafruit-max98357-i2s-class-d-mono-amp/pinouts), and [speaker example](https://www.adafruit.com/product/3968).

Use one planned power input. When programming from a computer, avoid connecting an external 5 V feed and USB power simultaneously unless the specific board's power arrangement explicitly permits it. Do not power the lights or amplifier from the ESP32's 3.3 V pin.

## Version A — RGB light + speaker

Add these parts to the shared components:

| Qty | Component | Specification / purpose |
|---|---|---|
| 10 | 5 mm diffused addressable RGB LEDs | 5 V, NeoPixel/WS2812-compatible 800 kHz protocol. Example: Adafruit 1938, sold in packs of five, so two packs per device. Ordinary four-leg analog RGB LEDs are not substitutes. |
| 1 | 74AHCT125 logic-level shifter | Powered at 5 V; converts GPIO4's 3.3 V data signal to 5 V. Enable the used channel by grounding its active-low output-enable pin; tie unused inputs to defined levels. |
| 1 | 330-ohm resistor, 1/4 W | In series with the shifted data signal, close to the first LED's DIN. |
| 10 | 100 nF ceramic capacitors | One across 5 V/GND at each through-hole pixel. |
| 1 | 100 nF ceramic capacitor | Close to the 74AHCT125 supply pins. |
| 1 | 1000 microfarad electrolytic capacitor, rated at least 10 V | Across the LED 5 V/GND supply, observing polarity. |

Connect GPIO4 → level shifter → 330-ohm resistor → first DIN. Chain each DOUT to the next DIN. Connect every LED's supply pins to the shared 5 V/GND rails.

[Adafruit's 5 mm pixels](https://www.adafruit.com/product/1938) use RGB color order, while the current Lily code uses GRB. Change the color order for these parts. That example was listed out of stock when checked; any substitute needs its own pinout, color-order and current check. Follow the manufacturer's [level-shifting, resistor and bulk-capacitor guidance](https://learn.adafruit.com/adafruit-neopixel-uberguide/best-practices) and [through-hole pixel decoupling guidance](https://learn.adafruit.com/adafruit-neopixel-uberguide/basic-connections).

Power estimate: reserving a conservative 60 mA per generic RGB pixel gives 0.6 A for ten pixels. Actual consumption depends on the selected LED and brightness. The 5 V/3 A supply recommendation includes margin for audio and the ESP32; do not extend the LED count without recalculating.

## Version B — ordinary white light + speaker

Add these parts to the shared components:

| Qty | Component | Specification / purpose |
|---|---|---|
| 10 | Ordinary 5 mm diffused warm-white LEDs | Prefer 2700–3000 K; select parts with documented forward voltage around 2.8–3.2 V at the intended current, and a continuous current rating of at least 10 mA. |
| 10 | 220-ohm resistors, 1/4 W | One per LED. With the assumed forward voltage and 5 V supply, each branch draws approximately 8–10 mA. Recalculate if the purchased LED has different specifications. |
| 1 | AO3400A N-channel MOSFET on a breakout/adapter PCB | Switches the combined LED current; its on-resistance is specified at 2.5 V gate drive, suitable for a 3.3 V GPIO. The bare part is surface-mount SOT-23. |
| 1 | 100-ohm resistor | Between GPIO18 and MOSFET gate. |
| 1 | 10-kilohm resistor | Between MOSFET gate and source; keeps the lights off during reset. |

Each branch is: 5 V → its own 220-ohm resistor → LED anode; LED cathode → MOSFET drain. MOSFET source → GND. GPIO18 drives the gate through 100 ohms. All ten branches share the MOSFET, but each has its own current-limiting resistor. Expected total LED current is approximately 80–100 mA under the stated assumptions.

The driver supports on/off and PWM brightness once implemented in firmware. Do not connect all ten LEDs directly to a GPIO. See the [AO3400A manufacturer datasheet](https://www.aosmd.com/sites/default/files/res/datasheets/AO3400A.pdf). This resistor-based circuit is for small indicator-style LEDs; high-power LEDs require a different driver and thermal design.

## Pin connections

| ESP32-S3 pin | Connection |
|---|---|
| GPIO4 | RGB data via level shifter — RGB version only |
| GPIO18 | White LED MOSFET gate circuit — white version only |
| GPIO12 | MAX98357A BCLK |
| GPIO13 | MAX98357A LRC / WS |
| GPIO14 | MAX98357A DIN |
| GND | Common circuit ground |

These signals do not overlap. Pins 15/16/17 are reserved in the project for a future microphone; a microphone is not needed for playback.

## Project compatibility findings

- `esp32_device` already uses NeoPixel lighting and MAX98357A-compatible I2S audio pins. It currently declares one pixel and updates only pixel zero. Ten LEDs require changing the pixel count and updating every pixel; the selected 5 mm example also needs RGB color order.
- `esp32_test_light` is an on/off LED test without audio support. For white light with sound, adapt the full audio firmware to drive the white LED MOSFET and expose white-light controls/capabilities in the application. This has not been implemented by this component-list task.
- The white test example and README specify GPIO18, but the local active configuration specifies GPIO37. GPIO37 is unavailable on ESP32-S3 variants using octal PSRAM. Use GPIO18 for the proposed white driver. See [Espressif's board guide](https://documentation.espressif.com/esp-dev-kits/en/latest/esp32s3/esp32-s3-devkitc-1/user_guide_v1.0.html).
- The current build specifies 16 MB flash but does not explicitly configure PSRAM. Confirm the existing board's actual flash/PSRAM and configure both the board target and audio build accordingly before declaring playback validated.
- The cloud/bear enclosure has ten provisional 5.3 mm LED holes and a 66 × 31 mm board cradle. Measure the existing board and chosen LED bodies/collars. Addressable LEDs have four leads, so routing clearance also needs checking.
- The enclosure has no dedicated speaker mount or acoustic openings. A 40 mm speaker, amplifier and driver/distribution PCB need a placement and enclosure revision before physical fit can be confirmed.

Recommendation: use the same ESP32-S3, MAX98357A and speaker for both versions. Change only the lighting components and lighting firmware. This is a documented prototype bill of materials, not a physically tested assembly.
