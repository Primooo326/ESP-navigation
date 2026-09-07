#include "display/GC9A01Display.h"

GC9A01Display::GC9A01Display(uint8_t dc, uint8_t cs, uint8_t sclk, uint8_t mosi, int8_t rst, uint8_t bl, ITouchController *touch)
    : _pinDc(dc), _pinCs(cs), _pinSclk(sclk), _pinMosi(mosi), _pinRst(rst), _pinBl(bl),
      _bus(nullptr), _gfx(nullptr), _touchController(touch), _brightnessLevel(255)
{
}

GC9A01Display::~GC9A01Display()
{
  if (_gfx)
    delete _gfx;
  if (_bus)
    delete _bus;
}

bool GC9A01Display::begin()
{
  pinMode(_pinBl, OUTPUT);
  analogWrite(_pinBl, _brightnessLevel);

  if (_touchController)
  {
    _touchController->begin();
  }

  _bus = new Arduino_ESP32SPI(_pinDc, _pinCs, _pinSclk, _pinMosi, GFX_NOT_DEFINED);
  _gfx = new Arduino_GC9A01(_bus, _pinRst, 0 /* rotación */, true /* IPS */);

  if (!_gfx->begin())
  {
    return false;
  }

  _viewManager.setGfx(_gfx);
  _viewManager.init();

  return true;
}

void GC9A01Display::update()
{
  if (!_gfx)
    return;

  // 1. Procesar Gestos Táctiles
  if (_touchController)
  {
    uint8_t gesture = 0;
    uint16_t x = 0, y = 0;
    if (_touchController->update(gesture, x, y))
    {
      switch (gesture)
      {
      case GESTURE_SWIPE_LEFT:
        _viewManager.handleSwipeLeft();
        break;
      case GESTURE_SWIPE_RIGHT:
        _viewManager.handleSwipeRight();
        break;
      case GESTURE_SWIPE_DOWN:
        _viewManager.handleSwipeDown();
        break;
      case GESTURE_SWIPE_UP:
        _viewManager.handleSwipeUp();
        break;
      case GESTURE_SINGLE_TAP:
        _viewManager.handleTap(x, y, _brightnessLevel, _pinBl);
        break;
      }
    }
  }

  // 2. Actualización de la vista activa si implementa update()
  if (_viewManager.getActiveView())
  {
    _viewManager.getActiveView()->update(_gfx);
  }
}

void GC9A01Display::renderStatus(const BLEStatus &status)
{
  _viewManager.dispatchStatus(status);
}

void GC9A01Display::renderSensorData(const SensorData &data)
{
  _viewManager.dispatchSensorData(data);
}

void GC9A01Display::renderNavigationData(const NavigationPacket &navData)
{
  _viewManager.dispatchNavigationData(navData);
}
