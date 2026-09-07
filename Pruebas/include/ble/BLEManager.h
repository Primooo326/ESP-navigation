#ifndef BLE_MANAGER_H
#define BLE_MANAGER_H

#include "../interfaces/IBLEStatusListener.h"
#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>
#include <BLE2902.h>

class BLEManager
{
private:
  String _deviceName;
  IBLEStatusListener *_listener;
  BLEStatus _currentStatus;

  BLEServer *_pServer;
  BLEService *_pService;
  BLECharacteristic *_pCharacteristic;

  bool _deviceConnected;
  bool _oldDeviceConnected;

  SensorData _latestSensorData;
  volatile bool _hasNewSensorData;

  NavigationPacket _latestNavData;
  volatile bool _hasNewNavData;

  void setStatus(BLEState state, const String &detail = "", int rssi = 0);

  friend class ManagerServerCallbacks;
  friend class ManagerCharacteristicCallbacks;

public:
  BLEManager(const String &deviceName, IBLEStatusListener *listener = nullptr);
  ~BLEManager() = default;

  void setListener(IBLEStatusListener *listener);
  void init();
  void update();
};

#endif // BLE_MANAGER_H
