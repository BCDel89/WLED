#include <Arduino.h>
#include <LittleFS.h>

void setup() {
  Serial.begin(115200);
  delay(200);

  Serial.println("\n[FS-Formatter] Mounting LittleFS at /littlefs with formatOnFail=true ...");
  if (!LittleFS.begin(true, "/littlefs", 10)) { // true = format on fail
    Serial.println("[FS-Formatter] LittleFS.begin FAILED");
    return;
  }
  Serial.println("[FS-Formatter] Mounted OK");

  File f = LittleFS.open("/littlefs/health.txt", FILE_WRITE);
  if (!f) {
    Serial.println("[FS-Formatter] Open for write failed");
  } else {
    f.println("hello from formatter");
    f.close();
    Serial.println("[FS-Formatter] Wrote /littlefs/health.txt");
  }
}

void loop() { delay(1000); }
