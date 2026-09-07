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

enum class TurnIcon : uint8_t
{
  NONE = 0,
  STRAIGHT = 1,
  TURN_RIGHT = 2,
  TURN_LEFT = 3,
  SLIGHT_RIGHT = 4,
  SLIGHT_LEFT = 5,
  SHARP_RIGHT = 6,
  SHARP_LEFT = 7,
  ROUNDABOUT_EXIT1 = 8,
  ARRIVED = 9,
  ROUNDABOUT_EXIT2 = 10,
  ROUNDABOUT_EXIT3 = 11,
  ROUNDABOUT_EXIT4 = 12,
  U_TURN = 13,
  FORK_RIGHT = 14,
  FORK_LEFT = 15,
  ON_RAMP = 16,
  OFF_RAMP = 17
};

#pragma pack(push, 1)
struct __attribute__((packed)) NavigationPacket
{
  uint8_t packetType;            // 1 = Navigation TBT Data
  uint8_t navState;              // 0 = Idle (Sin Navegacion), 1 = Active Navigation, 2 = Arrived
  uint8_t turnIcon;              // TurnIcon enum value
  uint16_t distanceMeters;       // Distancia al siguiente giro (0-65535)
  uint32_t totalRemainingMeters; // Metros restantes totales del viaje
  uint8_t speedKmh;              // Velocidad (0-255 km/h)
  uint16_t headingDeg;           // Rumbo relativo maniobra (0-360)
  uint16_t vehicleHeadingDeg;    // Brújula real del vehículo (0-360)
  uint8_t currentHour;           // Hora (0-23)
  uint8_t currentMinute;         // Minuto (0-59)
  int8_t temperatureC;           // Temperatura en grados Celsius (-50 a +50)
  uint8_t weatherCode;           // Código de condición Open-Meteo
  uint16_t finalHeadingDeg;      // Rumbo relativo hacia el punto final (0-360)
  char streetName[12];           // Nombre corto de la calle (null-terminated)

  NavigationPacket()
      : packetType(1), navState(0), turnIcon(0), distanceMeters(0),
        totalRemainingMeters(0), speedKmh(0), headingDeg(0),
        vehicleHeadingDeg(0), currentHour(12), currentMinute(0),
        temperatureC(20), weatherCode(0), finalHeadingDeg(0)
  {
    memset(streetName, 0, sizeof(streetName));
  }
};
#pragma pack(pop)

#endif // BLE_TYPES_H
