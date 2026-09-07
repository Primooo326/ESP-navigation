#include "touch/CST816STouchController.h"

CST816STouchController::CST816STouchController(uint8_t sda, uint8_t scl, uint8_t address)
    : _pinSda(sda), _pinScl(scl), _address(address), _wasTouchedPrev(false),
      _touchStartMs(0), _startX(0), _startY(0), _lastX(0), _lastY(0),
      _lastGestureEmitMs(0), _lastHwGesture(0)
{
}

bool CST816STouchController::begin()
{
  Wire.begin(_pinSda, _pinScl);
  return true;
}

bool CST816STouchController::update(uint8_t &gesture, uint16_t &x, uint16_t &y)
{
  uint32_t now = millis();

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

  // Al levantar el dedo de la pantalla: Resetear todos los pestillos de gestos y estado
  if (!isCurrentlyTouched)
  {
    if (_wasTouchedPrev)
    {
      // Procesar gesto al soltar si no vino por hardware
      uint32_t duration = now - _touchStartMs;
      int16_t dx = (int16_t)_lastX - (int16_t)_startX;
      int16_t dy = (int16_t)_lastY - (int16_t)_startY;

      _wasTouchedPrev = false;
      _lastHwGesture = GESTURE_NONE;

      if (now - _lastGestureEmitMs >= 350)
      {
        if (abs(dx) > 30 && abs(dx) > abs(dy))
        {
          _lastGestureEmitMs = now;
          gesture = (dx > 0) ? GESTURE_SWIPE_RIGHT : GESTURE_SWIPE_LEFT;
          return true;
        }
        else if (abs(dy) > 30 && abs(dy) > abs(dx))
        {
          _lastGestureEmitMs = now;
          gesture = (dy > 0) ? GESTURE_SWIPE_DOWN : GESTURE_SWIPE_UP;
          return true;
        }
        else if (duration < 500 && abs(dx) < 20 && abs(dy) < 20)
        {
          _lastGestureEmitMs = now;
          gesture = GESTURE_SINGLE_TAP;
          return true;
        }
      }
    }

    _wasTouchedPrev = false;
    _lastHwGesture = GESTURE_NONE;
    return false;
  }

  // Cooldown de 350ms entre gestos emitidos
  if (now - _lastGestureEmitMs < 350)
  {
    _wasTouchedPrev = isCurrentlyTouched;
    return false;
  }

  // Si el hardware CST816S reporta un gesto y aún no ha sido emitido en esta pulsación
  if (hwGesture != GESTURE_NONE)
  {
    if (_lastHwGesture == GESTURE_NONE)
    {
      _lastHwGesture = hwGesture;
      _lastGestureEmitMs = now;
      gesture = hwGesture;
      _wasTouchedPrev = isCurrentlyTouched;
      return true;
    }
    return false;
  }

  // Si recién inicia el toque por software
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

  // Mientras se mantiene presionado (Long Press si supera 1.2s)
  if (isCurrentlyTouched && _wasTouchedPrev)
  {
    _lastX = x;
    _lastY = y;
    if (_touchStartMs > 0 && (now - _touchStartMs > 1200))
    {
      _touchStartMs = 0;
      _lastGestureEmitMs = now;
      _lastHwGesture = GESTURE_LONG_PRESS;
      gesture = GESTURE_LONG_PRESS;
      return true;
    }
    return false;
  }

  return false;
}
