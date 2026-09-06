#ifndef IDISPLAY_H
#define IDISPLAY_H

#include "BLETypes.h"

class IDisplay
{
public:
  virtual ~IDisplay() = default;
  virtual bool begin() = 0;
  virtual void renderStatus(const BLEStatus &status) = 0;
  virtual void renderSensorData(const SensorData &data) = 0;
};

#endif // IDISPLAY_H
