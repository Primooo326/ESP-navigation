#ifndef BLE_TYPES_H
#define BLE_TYPES_H

#include <Arduino.h>

enum class BLEState
{
  INIT,
  ADVERTISING,
  CONNECTED,
  DISCONNECTED
};

struct BLEStatus
{
  BLEState state;
  String detail;
  int rssi;

  BLEStatus(BLEState s = BLEState::INIT, const String &d = "", int r = 0)
      : state(s), detail(d), rssi(r) {}
};

struct SensorData
{
  float accX;
  float accY;
  float accZ;

  float gyroX;
  float gyroY;
  float gyroZ;

  float heading; // Brújula (0 - 360 grados)
  bool updated;

  SensorData()
      : accX(0.0f), accY(0.0f), accZ(0.0f),
        gyroX(0.0f), gyroY(0.0f), gyroZ(0.0f),
        heading(0.0f), updated(false) {}
};

#endif // BLE_TYPES_H
