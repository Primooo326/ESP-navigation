#include "display/views/CatalogPreviewView.h"
#include "display/views/ViewUtils.h"

CatalogPreviewView::CatalogPreviewView()
    : _lastIcon(255)
{
  memset(_lastStreet, 0, sizeof(_lastStreet));
}

void CatalogPreviewView::drawTurnArrow(Arduino_GFX *gfx, uint8_t turnIcon, int cx, int cy, uint16_t color)
{
  gfx->fillRect(cx - 43, cy - 43, 86, 86, RGB565_BLACK);

  uint16_t iconColor = (turnIcon == 9) ? RGB565_GREEN : color;
  const uint8_t *xbm = getNavIconXBM(turnIcon);

  if (xbm)
  {
    gfx->drawXBitmap(cx - 40, cy - 40, xbm, 80, 80, iconColor);
  }
}

void CatalogPreviewView::onEnter(Arduino_GFX *gfx)
{
  if (!gfx) return;
  gfx->fillScreen(RGB565_BLACK);
  gfx->drawCircle(120, 120, 118, RGB565_DARKGREY);
  gfx->drawCircle(120, 120, 117, RGB565_DARKGREY);

  ViewUtils::drawCenteredText(gfx, "[ MODULO CATALOGO ]", 25, 1, RGB565_YELLOW);

  _lastIcon = 255;
  memset(_lastStreet, 0, sizeof(_lastStreet));

  renderNavigationData(gfx, _lastNav);
}

void CatalogPreviewView::onExit(Arduino_GFX *gfx)
{
  if (gfx) gfx->fillScreen(RGB565_BLACK);
}

void CatalogPreviewView::renderNavigationData(Arduino_GFX *gfx, const NavigationPacket &nav)
{
  if (!gfx) return;
  _lastNav = nav;

  // Solo dibuja el ícono si cambió
  if (nav.turnIcon != _lastIcon)
  {
    _lastIcon = nav.turnIcon;
    drawTurnArrow(gfx, nav.turnIcon, 120, 75, RGB565_WHITE);
  }

  // Solo dibuja el texto si cambió
  if (strncmp(_lastStreet, nav.streetName, sizeof(_lastStreet)) != 0)
  {
    strncpy(_lastStreet, nav.streetName, sizeof(_lastStreet) - 1);
    _lastStreet[sizeof(_lastStreet) - 1] = '\0';

    String rawText = (strlen(nav.streetName) > 0) ? String(nav.streetName) : String(getNavManeuverText(nav.turnIcon));
    String writtenText = sanitizeUTF8(rawText);
    uint8_t textSize = (writtenText.length() > 14) ? 1 : 2;
    ViewUtils::drawCenteredText(gfx, writtenText, 162, textSize, RGB565_CYAN);
  }
}
