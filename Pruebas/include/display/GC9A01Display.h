#ifndef GC9A01_DISPLAY_H
#define GC9A01_DISPLAY_H

#include "../interfaces/IDisplay.h"
#include "../interfaces/ITouchController.h"
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
  ITouchController *_touchController;

  // Touch & View States
  uint8_t _activeView; // 0 = Nav HUD / Primary, 1 = Clock & Weather Dashboard
  uint32_t _lastTouchMillis;

  // Estado del renderizado diferencial anti-parpadeo
  bool _sensorUiInitialized;
  int _lastNeedleX;
  int _lastNeedleY;

  BLEStatus _lastBleStatus;
  NavigationPacket _lastNavData;
  bool _hasActiveNavigation;

  uint16_t getRingColor(BLEState state) const;
  String getStateText(BLEState state) const;
  void drawStaticSensorUI();

  void drawCenteredText(const String &text, int cy, uint8_t textSize, uint16_t textColor, uint16_t bgColor = RGB565_BLACK);

  void renderDisconnectedUI(const BLEStatus &status);
  void renderDashboardIdleUI(const NavigationPacket &navData);
  void renderNavigationHUDUI(const NavigationPacket &navData);
  void drawTurnArrow(uint8_t turnIcon, int cx, int cy, uint16_t color);

  void renderCurrentView();

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
