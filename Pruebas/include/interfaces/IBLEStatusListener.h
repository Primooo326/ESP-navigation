#ifndef IBLE_STATUS_LISTENER_H
#define IBLE_STATUS_LISTENER_H

#include "BLETypes.h"

class IBLEStatusListener
{
public:
  virtual ~IBLEStatusListener() = default;
  virtual void onBLEStatusChanged(const BLEStatus &status) = 0;
  virtual void onSensorDataReceived(const SensorData &data) = 0;
  virtual void onNavigationDataReceived(const NavigationPacket &navData) = 0;
};

#endif // IBLE_STATUS_LISTENER_H
