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

  // Touch & Multi-View States
  uint8_t _activeView; // 0 = Nav HUD, 1 = Compass Rose, 2 = Trip Stats, 3 = Clock/Weather
  uint32_t _lastTouchMillis;
  uint8_t _brightnessLevel; // 0-255 PWM
  uint8_t _rotation;        // 0 or 2 (0 deg vs 180 deg)
  uint8_t _themeIndex;      // 0 = Neon, 1 = Minimal, 2 = Cyberpunk
  bool _showQuickSettings;  // Swipe Down overlay active
  bool _peekNextManeuver;   // Tap Central preview mode

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
  void renderCompassRoseUI(const NavigationPacket &navData);
  void renderTripStatsUI(const NavigationPacket &navData);
  void renderQuickSettingsOverlay();
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
