#include "touch/CST816STouchController.h"

CST816STouchController::CST816STouchController(uint8_t sda, uint8_t scl, uint8_t address)
    : _pinSda(sda), _pinScl(scl), _address(address), _wasTouchedPrev(false),
      _touchStartMs(0), _startX(0), _startY(0), _lastX(0), _lastY(0)
{
}

bool CST816STouchController::begin()
{
  Wire.begin(_pinSda, _pinScl);
  return true;
}

bool CST816STouchController::update(uint8_t &gesture, uint16_t &x, uint16_t &y)
{
  Wire.beginTransmission(_address);
  Wire.write(0x01);
  if (Wire.endTransmission(false) != 0)
  {
    return false;
  }

  uint8_t bytesRead = Wire.requestFrom((uint8_t)_address, (uint8_t)6);
  if (bytesRead < 6)
  {
    return false;
  }

  uint8_t hwGesture = Wire.read(); // Reg 0x01: Gesture ID
  uint8_t points = Wire.read();    // Reg 0x02: Finger count
  uint8_t xHigh = Wire.read();     // Reg 0x03
  uint8_t xLow = Wire.read();      // Reg 0x04
  uint8_t yHigh = Wire.read();     // Reg 0x05
  uint8_t yLow = Wire.read();      // Reg 0x06

  x = ((xHigh & 0x0F) << 8) | xLow;
  y = ((yHigh & 0x0F) << 8) | yLow;

  bool isCurrentlyTouched = (points == 1 && x < 240 && y < 240);
  uint32_t now = millis();

  // Si el hardware CST816S ya reporta un gesto directo válido (Swipe Up/Down/Left/Right/LongPress)
  if (hwGesture != GESTURE_NONE)
  {
    gesture = hwGesture;
    _wasTouchedPrev = isCurrentlyTouched;
    return true;
  }

  // Si recién se detecta el toque (flanco de bajada / inicio)
  if (isCurrentlyTouched && !_wasTouchedPrev)
  {
    _wasTouchedPrev = true;
    _touchStartMs = now;
    _startX = x;
    _startY = y;
    _lastX = x;
    _lastY = y;
    return false;
  }

  // Mientras se mantiene presionado (detectar Long Press si supera 1.5s)
  if (isCurrentlyTouched && _wasTouchedPrev)
  {
    _lastX = x;
    _lastY = y;
    if (_touchStartMs > 0 && (now - _touchStartMs > 1500))
    {
      _touchStartMs = 0; // Evitar disparos repetidos
      gesture = GESTURE_LONG_PRESS;
      return true;
    }
    return false;
  }

  // Al soltar la pantalla (flanco de subida)
  if (!isCurrentlyTouched && _wasTouchedPrev)
  {
    _wasTouchedPrev = false;
    uint32_t duration = now - _touchStartMs;
    int16_t dx = (int16_t)_lastX - (int16_t)_startX;
    int16_t dy = (int16_t)_lastY - (int16_t)_startY;

    // Gestos calculados por software si no vinieron por hardware
    if (abs(dx) > 35 && abs(dx) > abs(dy))
    {
      gesture = (dx > 0) ? GESTURE_SWIPE_RIGHT : GESTURE_SWIPE_LEFT;
      return true;
    }
    else if (abs(dy) > 35 && abs(dy) > abs(dx))
    {
      gesture = (dy > 0) ? GESTURE_SWIPE_DOWN : GESTURE_SWIPE_UP;
      return true;
    }
    else if (duration < 500 && abs(dx) < 20 && abs(dy) < 20)
    {
      gesture = GESTURE_SINGLE_TAP;
      return true;
    }
  }

  return false;
}
