#ifndef GC9A01_DISPLAY_H
#define GC9A01_DISPLAY_H

#include "../interfaces/IDisplay.h"
#include "../interfaces/ITouchController.h"
#include "ViewManager.h"
#include <Arduino_GFX_Library.h>

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
  ITouchController *_touchController;

  ViewManager _viewManager;
  uint8_t _brightnessLevel;

public:
  GC9A01Display(uint8_t dc, uint8_t cs, uint8_t sclk, uint8_t mosi, int8_t rst, uint8_t bl, ITouchController *touch = nullptr);
  ~GC9A01Display() override;

  void setTouchController(ITouchController *touch) { _touchController = touch; }

  bool begin() override;
  void update() override;
  void renderStatus(const BLEStatus &status) override;
  void renderSensorData(const SensorData &data) override;
  void renderNavigationData(const NavigationPacket &navData) override;
};

#endif // GC9A01_DISPLAY_H
