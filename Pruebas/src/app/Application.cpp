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

    // Renderizar inmediatamente la UI Shadcn Standby en el arranque
    NavigationPacket initialHud;
    initialHud.turnIcon = 1; // Flecha recto por defecto
    initialHud.distanceMeters = 0;
    initialHud.speedKmh = 0;
    initialHud.currentHour = 12;
    initialHud.currentMinute = 0;
    snprintf(initialHud.streetName, sizeof(initialHud.streetName), "Smart HUD");
    _display.renderNavigationData(initialHud);
  }

  _bleManager.init();
}

void Application::loop()
{
  _bleManager.update();
  _display.update();
}

void Application::onBLEStatusChanged(const BLEStatus &status)
{
  _display.renderStatus(status);
}

void Application::onSensorDataReceived(const SensorData &data)
{
  _display.renderSensorData(data);
}

void Application::onNavigationDataReceived(const NavigationPacket &navData)
{
  _display.renderNavigationData(navData);
}
