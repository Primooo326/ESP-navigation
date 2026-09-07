#include "display/views/TripStatsView.h"
#include "display/views/ViewUtils.h"

void TripStatsView::onEnter(Arduino_GFX *gfx)
{
  if (!gfx) return;
  gfx->fillScreen(RGB565_BLACK);
  gfx->drawCircle(120, 120, 118, RGB565_DARKGREY);

  ViewUtils::drawCenteredText(gfx, "[ PANEL DE VIAJE ]", 25, 1, RGB565_GREEN);
  renderNavigationData(gfx, _lastNav);
}

void TripStatsView::onExit(Arduino_GFX *gfx)
{
  if (gfx) gfx->fillScreen(RGB565_BLACK);
}

void TripStatsView::renderNavigationData(Arduino_GFX *gfx, const NavigationPacket &nav)
{
  if (!gfx) return;
  _lastNav = nav;

  char speedBuf[20];
  snprintf(speedBuf, sizeof(speedBuf), "%d", nav.speedKmh);
  ViewUtils::drawCenteredText(gfx, speedBuf, 60, 4, RGB565_WHITE);
  ViewUtils::drawCenteredText(gfx, "KM / H", 100, 1, RGB565_YELLOW);

  char totalBuf[24];
  if (nav.totalRemainingMeters >= 1000)
    snprintf(totalBuf, sizeof(totalBuf), "Restante: %.1f km", nav.totalRemainingMeters / 1000.0f);
  else
    snprintf(totalBuf, sizeof(totalBuf), "Restante: %d m", nav.totalRemainingMeters);

  ViewUtils::drawCenteredText(gfx, totalBuf, 128, 2, RGB565_WHITE);

  char headingBuf[20];
  snprintf(headingBuf, sizeof(headingBuf), "Rumbo: %d deg", nav.vehicleHeadingDeg % 360);
  ViewUtils::drawCenteredText(gfx, headingBuf, 160, 1, RGB565_LIGHTGREY);

  ViewUtils::drawCenteredText(gfx, "Desliza Lateral", 188, 1, RGB565_DARKGREY);
}
