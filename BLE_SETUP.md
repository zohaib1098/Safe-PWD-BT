# Safe PWDs — ESP32 BLE Integration Guide

## What was added

| Feature | File |
|---|---|
| BLE service (connect/reconnect/send) | `lib/services/ble_service.dart` |
| Device pairing screen | `lib/ble/ble_pairing_page.dart` |
| Connection + battery status card | `lib/ble/ble_status_card.dart` |
| Settings page updated with BLE card | `lib/dashboard/settings_page.dart` |
| Notification service sends "V" to ESP32 | `lib/services/notification_service.dart` |
| BLE permissions in AndroidManifest | `android/app/src/main/AndroidManifest.xml` |
| New deps: flutter_blue_plus, permission_handler | `pubspec.yaml` |
| **Complete ESP32 firmware** | `esp32_firmware/safe_pwd_esp32.ino` |

---

## Flutter setup

```bash
flutter pub get
flutter run
```

Go to **Settings → ESP32 Wearable → Pair Device** to connect.

---

## ESP32 Arduino setup

1. Install **Arduino IDE** (2.x recommended)
2. Add ESP32 board: `https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json`
3. Install library: **NimBLE-Arduino** (by h2zero) via Library Manager
4. Open `esp32_firmware/safe_pwd_esp32.ino`
5. Select board: **ESP32 Dev Module**
6. Upload

### Wiring

```
Vibration Motor Circuit:
  GPIO 4 ──[1kΩ]──► NPN Base (2N2222 or S8050)
                     Collector ──► Motor (+)
                     Emitter   ──► GND
  Motor (-)         ──► GND
  Diode 1N4148 across motor (cathode to +)

Battery ADC (LiPo 3.7V):
  LiPo+ ──[100kΩ]──┬──[100kΩ]──► GND
                    └──► GPIO 34

LED: GPIO 2 (built-in)
```

---

## BLE Protocol

| Phone sends | ESP32 does |
|---|---|
| `V` | Vibrates 3× emergency pattern |
| `B?` | Replies `B:85` (battery %) |
| `P` | Replies `PONG` |

The app automatically sends `V` whenever an emergency notification fires.

---

## How auto-reconnect works

On app start, `BleService.init()` checks SharedPreferences for a saved device ID.
If found, it starts a 5-second reconnect timer loop until connection is re-established.
Once connected, the timer stops. On disconnect, it restarts automatically.
