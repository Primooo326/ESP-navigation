#include <Arduino.h>
#include "display/GC9A01Display.h"
#include "app/Application.h"

// ============================================================================
// CONFIGURACIÓN HARDWARE PINES GC9A01 (ESP32-C3)
// ============================================================================
#define TFT_SCLK 6
#define TFT_MOSI 7
#define TFT_DC 2
#define TFT_CS 10
#define TFT_RST -1
#define TFT_BL 3

// Nombre del Dispositivo BLE visible en Android
#define DEVICE_NAME "ESP32C3_BLE"

// ============================================================================
// INYECCIÓN DE DEPENDENCIAS Y PUNTO DE ENTRADA
// ============================================================================
// Instancia concreta del display GC9A01
GC9A01Display display(TFT_DC, TFT_CS, TFT_SCLK, TFT_MOSI, TFT_RST, TFT_BL);

// La aplicación principal depende únicamente de la abstracción IDisplay
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
