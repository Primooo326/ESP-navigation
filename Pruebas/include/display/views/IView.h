#ifndef IVIEW_H
#define IVIEW_H

#include <Arduino.h>
#include <Arduino_GFX_Library.h>
#include "../../interfaces/BLETypes.h"

enum class ViewId : uint8_t
{
  DISCONNECTED = 0,
  CLOCK_WEATHER = 1,
  NAVIGATION_HUD = 2,
  CATALOG_PREVIEW = 3,
  COMPASS_ROSE = 4,
  TRIP_STATS = 5,
  QUICK_SETTINGS = 6
};

class IView
{
public:
  virtual ~IView() = default;
  virtual ViewId getId() const = 0;

  // Ciclo de vida de la vista
  virtual void onEnter(Arduino_GFX *gfx) = 0;
  virtual void onExit(Arduino_GFX *gfx) = 0;
  virtual void update(Arduino_GFX *gfx) {}

  // Eventos de datos (Hooks opcionales por pantalla)
  virtual void renderStatus(Arduino_GFX *gfx, const BLEStatus &status) {}
  virtual void renderSensorData(Arduino_GFX *gfx, const SensorData &data) {}
  virtual void renderNavigationData(Arduino_GFX *gfx, const NavigationPacket &navData) {}
};

#endif // IVIEW_H
