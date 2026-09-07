#include <Arduino.h>
#include "touch/CST816STouchController.h"
#include "display/GC9A01Display.h"
#include "app/Application.h"

// ============================================================================
// CONFIGURACIÓN HARDWARE PINES GC9A01 & CST816S (ESP32-C3)
// ============================================================================
#define TFT_SCLK 6
#define TFT_MOSI 7
#define TFT_DC 2
#define TFT_CS 10
#define TFT_RST -1
#define TFT_BL 3

#define TOUCH_SDA 4
#define TOUCH_SCL 5

// Nombre del Dispositivo BLE visible en Android
#define DEVICE_NAME "ESP32C3_BLE"

// ============================================================================
// INYECCIÓN DE DEPENDENCIAS (PRINCIPIOS SOLID)
// ============================================================================
CST816STouchController touchController(TOUCH_SDA, TOUCH_SCL);
GC9A01Display display(TFT_DC, TFT_CS, TFT_SCLK, TFT_MOSI, TFT_RST, TFT_BL, &touchController);

Application app(display, DEVICE_NAME);

void setup()
{
  Serial.begin(115200);
  delay(1000);

  app.setup();
}

void loop()
{
  app.loop();
  delay(100);
}
