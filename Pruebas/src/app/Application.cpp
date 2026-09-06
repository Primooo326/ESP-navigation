#include "app/Application.h"

Application::Application(IDisplay &display, const String &targetBleDevice)
    : _display(display), _bleManager(targetBleDevice, this)
{
}

void Application::setup()
{
  Serial.println("\n--- ARRANQUE APLICACIÓN ESP32-C3 SENSORES ANDROID ---");

  if (!_display.begin())
  {
    Serial.println(">> [Application] Error al inicializar pantalla.");
  }
  else
  {
    Serial.println(">> [Application] Pantalla inicializada exitosamente.");
  }

  _bleManager.init();
}

void Application::loop()
{
  _bleManager.update();
}

void Application::onBLEStatusChanged(const BLEStatus &status)
{
  _display.renderStatus(status);
}

void Application::onSensorDataReceived(const SensorData &data)
{
  _display.renderSensorData(data);
}
