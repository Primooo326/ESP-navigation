#ifndef IDISPLAY_H
#define IDISPLAY_H

#include "BLETypes.h"

class IDisplay
{
public:
  virtual ~IDisplay() = default;
  virtual bool begin() = 0;
  virtual void update() {}
  virtual void renderStatus(const BLEStatus &status) = 0;
  virtual void renderSensorData(const SensorData &data) = 0;
  virtual void renderNavigationData(const NavigationPacket &navData) = 0;
};

#endif // IDISPLAY_H
