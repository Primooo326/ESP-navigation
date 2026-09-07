#include "display/views/ClockWeatherView.h"
#include "display/views/ViewUtils.h"

ClockWeatherView::ClockWeatherView()
    : _hasActiveNav(false), _lastHour(25), _lastMinute(60), _lastTemp(127), _lastWeatherCode(255), _lastHasActiveNav(false)
{
}

const char *ClockWeatherView::getWeatherDescription(uint8_t code) const
{
  if (code == 0) return "DESPEJADO";
  if (code >= 1 && code <= 3) return "PARC NUBILADO";
  if (code == 45 || code == 48) return "NIEBLA";
  if ((code >= 51 && code <= 65) || (code >= 80 && code <= 82)) return "LLUVIA";
  if ((code >= 71 && code <= 77) || (code >= 85 && code <= 86)) return "NIEVE";
  if (code >= 95) return "TORMENTA";
  return "CLIMA OK";
}

void ClockWeatherView::onEnter(Arduino_GFX *gfx)
{
  if (!gfx) return;
  gfx->fillScreen(RGB565_BLACK);
  gfx->drawCircle(120, 120, 118, RGB565_DARKGREY);
  gfx->drawCircle(120, 120, 117, RGB565_DARKGREY);

  ViewUtils::drawCenteredText(gfx, "[ RELOJ & CLIMA ]", 25, 1, RGB565_CYAN);

  // Forza el redibujado estático inicial
  _lastHour = 25;
  _lastMinute = 60;
  _lastTemp = 127;
  _lastWeatherCode = 255;
  _lastHasActiveNav = !_hasActiveNav;

  renderNavigationData(gfx, _lastNav);
}

void ClockWeatherView::onExit(Arduino_GFX *gfx)
{
  if (gfx) gfx->fillScreen(RGB565_BLACK);
}

void ClockWeatherView::renderNavigationData(Arduino_GFX *gfx, const NavigationPacket &nav)
{
  if (!gfx) return;
  _lastNav = nav;
  _hasActiveNav = (nav.navState == 1 || nav.navState == 2);

  // Dibujar Reloj únicamente si cambió la hora/minuto
  if (nav.currentHour != _lastHour || nav.currentMinute != _lastMinute)
  {
    _lastHour = nav.currentHour;
    _lastMinute = nav.currentMinute;

    int displayHour = nav.currentHour % 12;
    if (displayHour == 0) displayHour = 12;
    const char *ampm = (nav.currentHour >= 12) ? "PM" : "AM";
    char clockBuf[16];
    snprintf(clockBuf, sizeof(clockBuf), "%02d:%02d %s", displayHour, nav.currentMinute, ampm);
    ViewUtils::drawCenteredText(gfx, clockBuf, 65, 3, RGB565_WHITE);
  }

  // Dibujar Clima únicamente si cambió la temperatura o el código
  if (nav.temperatureC != _lastTemp || nav.weatherCode != _lastWeatherCode)
  {
    _lastTemp = nav.temperatureC;
    _lastWeatherCode = nav.weatherCode;

    char weatherBuf[24];
    snprintf(weatherBuf, sizeof(weatherBuf), "%d C  %s", nav.temperatureC, getWeatherDescription(nav.weatherCode));
    ViewUtils::drawCenteredText(gfx, weatherBuf, 115, 2, RGB565_YELLOW);
  }

  // Dibujar estado de navegación únicamente si cambió
  if (_hasActiveNav != _lastHasActiveNav)
  {
    _lastHasActiveNav = _hasActiveNav;
    if (_hasActiveNav)
    {
      ViewUtils::drawCenteredText(gfx, "NAVEGACION ACTIVA", 165, 1, RGB565_GREEN);
    }
    else
    {
      ViewUtils::drawCenteredText(gfx, "SIN NAVEGACION ACTIVA", 165, 1, RGB565_LIGHTGREY);
    }
  }
}
