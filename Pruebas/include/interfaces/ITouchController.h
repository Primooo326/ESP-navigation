#ifndef I_TOUCH_CONTROLLER_H
#define I_TOUCH_CONTROLLER_H

#include <Arduino.h>

enum TouchGesture {
  GESTURE_NONE = 0x00,
  GESTURE_SWIPE_UP = 0x01,
  GESTURE_SWIPE_DOWN = 0x02,
  GESTURE_SWIPE_LEFT = 0x03,
  GESTURE_SWIPE_RIGHT = 0x04,
  GESTURE_SINGLE_TAP = 0x05,
  GESTURE_DOUBLE_TAP = 0x0B,
  GESTURE_LONG_PRESS = 0x0C
};

class ITouchController
{
public:
  virtual ~ITouchController() = default;
  virtual bool begin() = 0;
  virtual bool update(uint8_t &gesture, uint16_t &x, uint16_t &y) = 0;
};

#endif // I_TOUCH_CONTROLLER_H
