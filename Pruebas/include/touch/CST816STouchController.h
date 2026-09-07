#ifndef CST816S_TOUCH_CONTROLLER_H
#define CST816S_TOUCH_CONTROLLER_H

#include "../interfaces/ITouchController.h"
#include <Wire.h>

class CST816STouchController : public ITouchController
{
private:
  uint8_t _pinSda;
  uint8_t _pinScl;
  uint8_t _address;
  bool _wasTouchedPrev;

public:
  CST816STouchController(uint8_t sda = 4, uint8_t scl = 5, uint8_t address = 0x15);
  ~CST816STouchController() override = default;

  bool begin() override;
  bool update(uint8_t &gesture, uint16_t &x, uint16_t &y) override;
};

#endif // CST816S_TOUCH_CONTROLLER_H
