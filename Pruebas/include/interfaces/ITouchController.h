#ifndef I_TOUCH_CONTROLLER_H
#define I_TOUCH_CONTROLLER_H

#include <Arduino.h>

class ITouchController
{
public:
  virtual ~ITouchController() = default;
  virtual bool begin() = 0;
  virtual bool update(uint8_t &gesture, uint16_t &x, uint16_t &y) = 0;
};

#endif // I_TOUCH_CONTROLLER_H
