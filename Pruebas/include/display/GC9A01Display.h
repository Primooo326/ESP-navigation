#ifndef GC9A01_DISPLAY_H
#define GC9A01_DISPLAY_H

#include "../interfaces/IDisplay.h"
#include <Arduino_GFX_Library.h>
#include <math.h>

class GC9A01Display : public IDisplay
{
private:
  uint8_t _pinDc;
  uint8_t _pinCs;
  uint8_t _pinSclk;
  uint8_t _pinMosi;
  int8_t _pinRst;
  uint8_t _pinBl;

  Arduino_DataBus *_bus;
  Arduino_GFX *_gfx;

  // Estado del renderizado diferencial anti-parpadeo
  bool _sensorUiInitialized;
  int _lastNeedleX;
  int _lastNeedleY;
  int _lastBubbleX;
  int _lastBubbleY;

  uint16_t getRingColor(BLEState state) const;
  String getStateText(BLEState state) const;
  void drawStaticSensorUI();

public:
  GC9A01Display(uint8_t dc, uint8_t cs, uint8_t sclk, uint8_t mosi, int8_t rst, uint8_t bl);
  ~GC9A01Display() override;

  bool begin() override;
  void renderStatus(const BLEStatus &status) override;
  void renderSensorData(const SensorData &data) override;
};

#endif // GC9A01_DISPLAY_H
