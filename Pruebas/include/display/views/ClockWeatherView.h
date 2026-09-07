#ifndef CLOCK_WEATHER_VIEW_H
#define CLOCK_WEATHER_VIEW_H

#include "IView.h"

class ClockWeatherView : public IView
{
private:
  NavigationPacket _lastNav;
  bool _hasActiveNav;

  uint8_t _lastHour;
  uint8_t _lastMinute;
  int8_t _lastTemp;
  uint8_t _lastWeatherCode;
  bool _lastHasActiveNav;

  const char *getWeatherDescription(uint8_t code) const;

public:
  ClockWeatherView();

  ViewId getId() const override { return ViewId::CLOCK_WEATHER; }

  void onEnter(Arduino_GFX *gfx) override;
  void onExit(Arduino_GFX *gfx) override;

  // Filtro estricto SOLID: Ignora datos de sensores (brújula) por completo
  void renderSensorData(Arduino_GFX *gfx, const SensorData &data) override {}

  void renderNavigationData(Arduino_GFX *gfx, const NavigationPacket &navData) override;
};

#endif // CLOCK_WEATHER_VIEW_H
