/**
 * ============================================================
 *  Safe PWDs — ESP32 Wearable BLE Firmware
 *  File: safe_pwd_esp32.ino
 *
 *  Features:
 *  ✅ BLE UART (Nordic UART Service) — auto-advertises
 *  ✅ Receives "V" command → triggers vibration motor
 *  ✅ Receives "B?" command → replies with battery level "B:XX"
 *  ✅ Sends status messages back to phone
 *  ✅ LED status indicator (on-board LED)
 *  ✅ Deep-sleep friendly reconnect loop
 *
 *  WIRING:
 *  ──────────────────────────────────────────────
 *  Vibration Motor  →  GPIO 4  (via NPN transistor)
 *  Battery ADC      →  GPIO 34 (voltage divider: 100k + 100k)
 *  On-board LED     →  GPIO 2  (built-in on most ESP32 boards)
 *
 *  Motor circuit (drives 3V–5V coin vibration motor):
 *    GPIO 4 ──[1kΩ]──► NPN Base (e.g. 2N2222 / S8050)
 *                       Collector ──► Motor (+)
 *                       Emitter   ──► GND
 *    Motor (-)         ──► GND
 *    Flyback diode 1N4148 across motor (cathode to +)
 *
 *  Battery sensing (3.7V LiPo → 3.3V ADC safe):
 *    LiPo+ ──[100kΩ]──┬──[100kΩ]──► GND
 *                      └──► GPIO 34
 *  (Divides 4.2V max → 2.1V, well within 3.3V ADC range)
 *
 *  DEPENDENCIES (Arduino Library Manager):
 *    • NimBLE-Arduino  (by h2zero)  ← lightweight, recommended
 *      Install: Library Manager → search "NimBLE-Arduino"
 *
 *  BOARD: ESP32 Dev Module (or any ESP32 variant)
 *  ============================================================
 */

#include <NimBLEDevice.h>

// ── Pin Definitions ──────────────────────────────────────────
#define VIBRATION_PIN   4    // NPN transistor base drive
#define BATTERY_PIN     34   // Analog input (voltage divider)
#define LED_PIN         2    // On-board LED (active HIGH on most boards)

// ── Vibration Settings ───────────────────────────────────────
#define VIB_DURATION_MS 1000  // Single vibration pulse duration
#define VIB_PATTERN_ON  500
#define VIB_PATTERN_OFF 300
#define VIB_REPEAT      3     // Number of pulses for emergency

// ── Battery ADC ──────────────────────────────────────────────
#define BAT_ADC_MAX     4095
#define BAT_V_REF       3.3f   // ESP32 ADC reference voltage
#define BAT_DIVIDER_R   2.0f   // Ratio = (R1+R2)/R2 = (100k+100k)/100k = 2
#define BAT_FULL_V      4.2f   // LiPo full voltage
#define BAT_EMPTY_V     3.0f   // LiPo empty voltage

// ── BLE UUIDs (Nordic UART Service) ─────────────────────────
#define UART_SERVICE_UUID  "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define TX_CHAR_UUID       "6E400003-B5A3-F393-E0A9-E50E24DCCA9E" // Notify → Phone
#define RX_CHAR_UUID       "6E400002-B5A3-F393-E0A9-E50E24DCCA9E" // Write ← Phone

// ── Device Name ──────────────────────────────────────────────
#define DEVICE_NAME "SafePWD"

// ── Globals ──────────────────────────────────────────────────
NimBLEServer*          pServer      = nullptr;
NimBLECharacteristic*  pTxChar      = nullptr;  // Notify phone
NimBLECharacteristic*  pRxChar      = nullptr;  // Receive from phone
bool                   deviceConnected = false;
bool                   oldConnected    = false;

// ── Forward declarations ──────────────────────────────────────
void vibrateEmergency();
void vibrateSingle(uint32_t ms);
int  getBatteryPercent();
void sendToPhone(const String& msg);
void blinkLED(int times, int onMs = 100, int offMs = 100);

// ─────────────────────────────────────────────────────────────
//  BLE Server Callbacks
// ─────────────────────────────────────────────────────────────
class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* pSvr) override {
    deviceConnected = true;
    Serial.println("[BLE] Phone connected!");
    blinkLED(3, 200, 100);
    sendToPhone("Hello from SafePWD Wearable!");
  }

  void onDisconnect(NimBLEServer* pSvr) override {
    deviceConnected = false;
    Serial.println("[BLE] Phone disconnected. Restarting advertising...");
    // Restart advertising so phone can reconnect
    NimBLEDevice::startAdvertising();
  }
};

// ─────────────────────────────────────────────────────────────
//  RX Characteristic Callbacks (commands from phone)
// ─────────────────────────────────────────────────────────────
class RxCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* pChar) override {
    std::string rxVal = pChar->getValue();
    if (rxVal.empty()) return;

    String cmd = String(rxVal.c_str());
    cmd.trim();
    Serial.print("[BLE] Received command: ");
    Serial.println(cmd);

    // ── "V" → Vibrate emergency pattern ─────────────────────
    if (cmd == "V") {
      Serial.println("[CMD] Emergency vibration triggered!");
      sendToPhone("OK:V");
      vibrateEmergency();
    }

    // ── "B?" → Reply with battery level ──────────────────────
    else if (cmd == "B?") {
      int pct = getBatteryPercent();
      String reply = "B:" + String(pct);
      Serial.print("[CMD] Battery query → ");
      Serial.println(reply);
      sendToPhone(reply);
    }

    // ── "P" → Simple ping ────────────────────────────────────
    else if (cmd == "P") {
      sendToPhone("PONG");
    }

    // ── Unknown ───────────────────────────────────────────────
    else {
      sendToPhone("ERR:UNKNOWN:" + cmd);
    }
  }
};

// ─────────────────────────────────────────────────────────────
//  setup()
// ─────────────────────────────────────────────────────────────
void setup() {
  Serial.begin(115200);
  Serial.println("\n[BOOT] Safe PWDs ESP32 Wearable starting...");

  // Pin modes
  pinMode(VIBRATION_PIN, OUTPUT);
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(VIBRATION_PIN, LOW);
  digitalWrite(LED_PIN, LOW);

  // ADC config for battery
  analogReadResolution(12);
  analogSetAttenuation(ADC_11db); // Allows reading up to ~3.9V

  // Boot blink
  blinkLED(2, 300, 200);

  // ── Init NimBLE ───────────────────────────────────────────
  NimBLEDevice::init(DEVICE_NAME);
  NimBLEDevice::setMTU(128);

  // Create server
  pServer = NimBLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  // Create UART service
  NimBLEService* pService = pServer->createService(UART_SERVICE_UUID);

  // TX characteristic (ESP32 → Phone, Notify)
  pTxChar = pService->createCharacteristic(
    TX_CHAR_UUID,
    NIMBLE_PROPERTY::NOTIFY
  );

  // RX characteristic (Phone → ESP32, Write)
  pRxChar = pService->createCharacteristic(
    RX_CHAR_UUID,
    NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR
  );
  pRxChar->setCallbacks(new RxCallbacks());

  // Start service
  pService->start();

  // Configure advertising
  NimBLEAdvertising* pAdvertising = NimBLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(UART_SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMaxPreferred(0x12);
  NimBLEDevice::startAdvertising();

  Serial.println("[BLE] Advertising as: " DEVICE_NAME);
  Serial.println("[BLE] Ready! Waiting for phone connection...");

  // Ready pulse
  vibrateSingle(200);
}

// ─────────────────────────────────────────────────────────────
//  loop()
// ─────────────────────────────────────────────────────────────
void loop() {
  // LED heartbeat: fast blink when connected, slow when advertising
  if (deviceConnected) {
    // Steady slow blink = connected
    digitalWrite(LED_PIN, HIGH);
    delay(50);
    digitalWrite(LED_PIN, LOW);
    delay(1950);
  } else {
    // Fast blink = advertising / waiting
    digitalWrite(LED_PIN, HIGH);
    delay(50);
    digitalWrite(LED_PIN, LOW);
    delay(450);
  }
}

// ─────────────────────────────────────────────────────────────
//  Vibration helpers
// ─────────────────────────────────────────────────────────────

/// Emergency pattern: 3 pulses
void vibrateEmergency() {
  for (int i = 0; i < VIB_REPEAT; i++) {
    digitalWrite(VIBRATION_PIN, HIGH);
    delay(VIB_PATTERN_ON);
    digitalWrite(VIBRATION_PIN, LOW);
    if (i < VIB_REPEAT - 1) delay(VIB_PATTERN_OFF);
  }
}

/// Single vibration for a given duration
void vibrateSingle(uint32_t ms) {
  digitalWrite(VIBRATION_PIN, HIGH);
  delay(ms);
  digitalWrite(VIBRATION_PIN, LOW);
}

// ─────────────────────────────────────────────────────────────
//  Battery percentage (LiPo 3.0V → 4.2V)
// ─────────────────────────────────────────────────────────────
int getBatteryPercent() {
  // Average multiple readings to reduce ADC noise
  long sum = 0;
  for (int i = 0; i < 16; i++) {
    sum += analogRead(BATTERY_PIN);
    delay(2);
  }
  float raw = sum / 16.0f;

  // Convert ADC → actual battery voltage (accounting for divider)
  float vAdc    = (raw / BAT_ADC_MAX) * BAT_V_REF;
  float vBat    = vAdc * BAT_DIVIDER_R;

  // Clamp and convert to percentage
  vBat = constrain(vBat, BAT_EMPTY_V, BAT_FULL_V);
  int pct = (int)(((vBat - BAT_EMPTY_V) / (BAT_FULL_V - BAT_EMPTY_V)) * 100.0f);

  Serial.printf("[BAT] ADC=%.0f  Vadc=%.2fV  Vbat=%.2fV  Level=%d%%\n",
                raw, vAdc, vBat, pct);
  return pct;
}

// ─────────────────────────────────────────────────────────────
//  Send string to phone via BLE Notify
// ─────────────────────────────────────────────────────────────
void sendToPhone(const String& msg) {
  if (!deviceConnected || pTxChar == nullptr) return;
  pTxChar->setValue(msg.c_str());
  pTxChar->notify();
  Serial.print("[BLE] Sent to phone: ");
  Serial.println(msg);
}

// ─────────────────────────────────────────────────────────────
//  LED blink helper
// ─────────────────────────────────────────────────────────────
void blinkLED(int times, int onMs, int offMs) {
  for (int i = 0; i < times; i++) {
    digitalWrite(LED_PIN, HIGH);
    delay(onMs);
    digitalWrite(LED_PIN, LOW);
    if (i < times - 1) delay(offMs);
  }
}
