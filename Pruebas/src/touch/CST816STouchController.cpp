#include "touch/CST816STouchController.h"

CST816STouchController::CST816STouchController(uint8_t sda, uint8_t scl, uint8_t address)
    : _pinSda(sda), _pinScl(scl), _address(address), _wasTouchedPrev(false)
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

  gesture = Wire.read();        // Reg 0x01: Gesture ID
  uint8_t points = Wire.read();  // Reg 0x02: Finger count
  uint8_t xHigh = Wire.read();   // Reg 0x03
  uint8_t xLow = Wire.read();    // Reg 0x04
  uint8_t yHigh = Wire.read();   // Reg 0x05
  uint8_t yLow = Wire.read();    // Reg 0x06

  x = ((xHigh & 0x0F) << 8) | xLow;
  y = ((yHigh & 0x0F) << 8) | yLow;

  bool isCurrentlyTouched = (points == 1 && x < 240 && y < 240);

  if (isCurrentlyTouched && !_wasTouchedPrev)
  {
    _wasTouchedPrev = true;
    return true; // Transición de flanco positivo: toque único
  }

  if (!isCurrentlyTouched)
  {
    _wasTouchedPrev = false;
  }

  return false;
}
