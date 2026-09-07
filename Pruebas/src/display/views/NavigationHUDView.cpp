#include "display/views/NavigationHUDView.h"
#include "display/views/ViewUtils.h"

NavigationHUDView::NavigationHUDView()
    : _lastEdgeX(-1), _lastEdgeY(-1), _lastNX(-1), _lastNY(-1), _lastFX(-1), _lastFY(-1)
{
}

void NavigationHUDView::drawTurnArrow(Arduino_GFX *gfx, uint8_t turnIcon, int cx, int cy, uint16_t color)
{
  gfx->fillRect(cx - 43, cy - 43, 86, 86, RGB565_BLACK);

  uint16_t iconColor = (turnIcon == 9) ? RGB565_GREEN : color;
  const uint8_t *xbm = getNavIconXBM(turnIcon);

  if (xbm)
  {
    gfx->drawXBitmap(cx - 40, cy - 40, xbm, 80, 80, iconColor);
  }
}

void NavigationHUDView::onEnter(Arduino_GFX *gfx)
{
  if (!gfx) return;
  gfx->fillScreen(RGB565_BLACK);
  gfx->drawCircle(120, 120, 118, RGB565_DARKGREY);
  gfx->drawCircle(120, 120, 117, RGB565_DARKGREY);

  _lastEdgeX = -1;
  _lastEdgeY = -1;
  _lastNX = -1;
  _lastNY = -1;
  _lastFX = -1;
  _lastFY = -1;

  renderNavigationData(gfx, _lastNav);
}

void NavigationHUDView::onExit(Arduino_GFX *gfx)
{
  if (gfx) gfx->fillScreen(RGB565_BLACK);
}

void NavigationHUDView::renderNavigationData(Arduino_GFX *gfx, const NavigationPacket &nav)
{
  if (!gfx) return;
  _lastNav = nav;

  // 0. Hora actual en la cabecera superior
  int displayHour = nav.currentHour % 12;
  if (displayHour == 0) displayHour = 12;
  const char *ampm = (nav.currentHour >= 12) ? "PM" : "AM";
  char clockHeaderBuf[16];
  snprintf(clockHeaderBuf, sizeof(clockHeaderBuf), "%02d:%02d %s", displayHour, nav.currentMinute, ampm);
  ViewUtils::drawCenteredText(gfx, clockHeaderBuf, 22, 1, RGB565_CYAN);

  // 1. Icono de maniobra central
  drawTurnArrow(gfx, nav.turnIcon, 120, 55, RGB565_WHITE);

  // 2. Distancia al siguiente giro
  char distBuf[16];
  if (nav.distanceMeters >= 1000)
    snprintf(distBuf, sizeof(distBuf), "%.1f km", nav.distanceMeters / 1000.0f);
  else
    snprintf(distBuf, sizeof(distBuf), "%d m", nav.distanceMeters);
  ViewUtils::drawCenteredText(gfx, distBuf, 106, 3, RGB565_WHITE);

  // 3. Metros restantes del viaje completo
  char totalBuf[24];
  if (nav.totalRemainingMeters >= 1000)
    snprintf(totalBuf, sizeof(totalBuf), "Restan: %.1f km", nav.totalRemainingMeters / 1000.0f);
  else
    snprintf(totalBuf, sizeof(totalBuf), "Restan: %d m", nav.totalRemainingMeters);
  ViewUtils::drawCenteredText(gfx, totalBuf, 136, 1, RGB565_LIGHTGREY);

  // 4. Nombre de la calle
  String rawStreet = (strlen(nav.streetName) > 0) ? String(nav.streetName) : String(getNavManeuverText(nav.turnIcon));
  String cleanStreet = sanitizeUTF8(rawStreet);
  ViewUtils::drawCenteredText(gfx, cleanStreet, 160, 2, RGB565_WHITE);

  // 5. Badge de velocidad
  char speedBuf[16];
  snprintf(speedBuf, sizeof(speedBuf), "%3d km/h", nav.speedKmh);
  ViewUtils::drawCenteredText(gfx, speedBuf, 190, 2, RGB565_YELLOW);

  // 6. CIRCULO VERDE EN EL BORDE CIRCULAR (Maniobra siguiente)
  float radTarget = ((int)nav.headingDeg - 90) * (M_PI / 180.0f);
  int edgeX = 120 + (int)(cos(radTarget) * 112.0f);
  int edgeY = 120 + (int)(sin(radTarget) * 112.0f);

  if (_lastEdgeX > 0 && (_lastEdgeX != edgeX || _lastEdgeY != edgeY))
  {
    gfx->fillCircle(_lastEdgeX, _lastEdgeY, 8, RGB565_BLACK);
  }
  gfx->fillCircle(edgeX, edgeY, 6, RGB565_GREEN);
  gfx->drawCircle(edgeX, edgeY, 7, RGB565_WHITE);
  _lastEdgeX = edgeX;
  _lastEdgeY = edgeY;

  // 7. LETRA 'N' EN EL BORDE CIRCULAR (Norte magnético)
  float radNorth = ((360 - (int)nav.vehicleHeadingDeg) - 90) * (M_PI / 180.0f);
  int nX = 120 + (int)(cos(radNorth) * 112.0f);
  int nY = 120 + (int)(sin(radNorth) * 112.0f);

  if (_lastNX > 0 && (_lastNX != nX || _lastNY != nY))
  {
    gfx->fillCircle(_lastNX, _lastNY, 9, RGB565_BLACK);
  }
  gfx->fillCircle(nX, nY, 8, RGB565_RED);
  gfx->setTextSize(1);
  gfx->setTextColor(RGB565_WHITE, RGB565_RED);
  gfx->setCursor(nX - 3, nY - 3);
  gfx->print("N");
  _lastNX = nX;
  _lastNY = nY;

  // 8. LETRA 'F' EN EL BORDE CIRCULAR (Destino final)
  float radFinal = ((int)nav.finalHeadingDeg - 90) * (M_PI / 180.0f);
  int fX = 120 + (int)(cos(radFinal) * 112.0f);
  int fY = 120 + (int)(sin(radFinal) * 112.0f);

  if (_lastFX > 0 && (_lastFX != fX || _lastFY != fY))
  {
    gfx->fillCircle(_lastFX, _lastFY, 9, RGB565_BLACK);
  }
  gfx->fillCircle(fX, fY, 8, RGB565_BLUE);
  gfx->setTextSize(1);
  gfx->setTextColor(RGB565_WHITE, RGB565_BLUE);
  gfx->setCursor(fX - 3, fY - 3);
  gfx->print("F");
  _lastFX = fX;
  _lastFY = fY;
}
