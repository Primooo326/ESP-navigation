#include "display/views/CompassRoseView.h"
#include "display/views/ViewUtils.h"

CompassRoseView::CompassRoseView()
    : _lastNeedleX(-1), _lastNeedleY(-1)
{
}

void CompassRoseView::onEnter(Arduino_GFX *gfx)
{
  if (!gfx) return;
  gfx->fillScreen(RGB565_BLACK);
  gfx->drawCircle(120, 120, 118, RGB565_DARKGREY);
  gfx->drawCircle(120, 120, 95, RGB565_DARKGREY);

  ViewUtils::drawCenteredText(gfx, "[ BRUJULA DIGITAL ]", 25, 1, RGB565_GREEN);
  ViewUtils::drawCenteredText(gfx, "N", 38, 1, RGB565_RED);
  ViewUtils::drawCenteredText(gfx, "S", 192, 1, RGB565_LIGHTGREY);

  _lastNeedleX = -1;
  _lastNeedleY = -1;

  renderNavigationData(gfx, _lastNav);
}

void CompassRoseView::onExit(Arduino_GFX *gfx)
{
  if (gfx) gfx->fillScreen(RGB565_BLACK);
}

void CompassRoseView::renderSensorData(Arduino_GFX *gfx, const SensorData &data)
{
  if (!gfx) return;

  float headingAngle = (360.0f - data.heading);
  float rad = (headingAngle - 90.0f) * (M_PI / 180.0f);

  int needleX = 120 + (int)(cos(rad) * 65.0f);
  int needleY = 120 + (int)(sin(rad) * 65.0f);

  if (_lastNeedleX > 0 && (_lastNeedleX != needleX || _lastNeedleY != needleY))
  {
    gfx->drawLine(120, 120, _lastNeedleX, _lastNeedleY, RGB565_BLACK);
    gfx->fillCircle(_lastNeedleX, _lastNeedleY, 5, RGB565_BLACK);
  }

  gfx->drawLine(120, 120, needleX, needleY, RGB565_RED);
  gfx->fillCircle(needleX, needleY, 5, RGB565_RED);
  gfx->fillCircle(120, 120, 4, RGB565_WHITE);

  _lastNeedleX = needleX;
  _lastNeedleY = needleY;

  char degBuf[20];
  int hInt = (int)data.heading % 360;
  if (hInt < 0) hInt += 360;
  snprintf(degBuf, sizeof(degBuf), "%3d deg", hInt);
  ViewUtils::drawCenteredText(gfx, degBuf, 110, 2, RGB565_WHITE);
}

void CompassRoseView::renderNavigationData(Arduino_GFX *gfx, const NavigationPacket &nav)
{
  if (!gfx) return;
  _lastNav = nav;

  SensorData simData;
  simData.heading = nav.vehicleHeadingDeg;
  renderSensorData(gfx, simData);

  char distBuf[24];
  if (nav.totalRemainingMeters >= 1000)
    snprintf(distBuf, sizeof(distBuf), "Restan: %.1f km", nav.totalRemainingMeters / 1000.0f);
  else
    snprintf(distBuf, sizeof(distBuf), "Restan: %d m", nav.totalRemainingMeters);
  ViewUtils::drawCenteredText(gfx, distBuf, 155, 1, RGB565_LIGHTGREY);
  ViewUtils::drawCenteredText(gfx, "Desliza Lateral", 188, 1, RGB565_DARKGREY);
}
