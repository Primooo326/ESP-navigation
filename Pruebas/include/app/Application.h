#ifndef APPLICATION_H
#define APPLICATION_H

#include "../interfaces/IDisplay.h"
#include "../interfaces/IBLEStatusListener.h"
#include "../ble/BLEManager.h"

class Application : public IBLEStatusListener
{
private:
  IDisplay &_display;
  BLEManager _bleManager;

public:
  Application(IDisplay &display, const String &targetBleDevice);
  ~Application() override = default;

  void setup();
  void loop();

  // Implementación del observer IBLEStatusListener
  void onBLEStatusChanged(const BLEStatus &status) override;
  void onSensorDataReceived(const SensorData &data) override;
};

#endif // APPLICATION_H
