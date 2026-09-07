#include "display/views/QuickSettingsView.h"
#include "display/views/ViewUtils.h"

QuickSettingsView::QuickSettingsView()
    : _brightness(255)
{
}

void QuickSettingsView::onEnter(Arduino_GFX *gfx)
{
  if (!gfx) return;
  gfx->fillScreen(RGB565_BLACK);
  gfx->drawCircle(120, 120, 118, RGB565_YELLOW);
  gfx->drawCircle(120, 120, 117, RGB565_YELLOW);

  ViewUtils::drawCenteredText(gfx, "[ CORTINILLA CONTROL ]", 25, 1, RGB565_YELLOW);
  gfx->drawFastHLine(30, 42, 180, RGB565_DARKGREY);

  ViewUtils::drawCenteredText(gfx, "BRILLO PANTALLA", 52, 1, RGB565_WHITE);

  // 1. Botón Menos "-"
  gfx->fillRoundRect(30, 75, 50, 50, 10, RGB565_DARKGREY);
  gfx->fillRect(43, 97, 24, 6, RGB565_WHITE);

  // 2. Botón Más "+"
  gfx->fillRoundRect(160, 75, 50, 50, 10, RGB565_DARKGREY);
  gfx->fillRect(173, 97, 24, 6, RGB565_WHITE);
  gfx->fillRect(182, 88, 6, 24, RGB565_WHITE);

  ViewUtils::drawCenteredText(gfx, "Desliza arriba: Cerrar", 180, 1, RGB565_LIGHTGREY);

  update(gfx);
}

void QuickSettingsView::onExit(Arduino_GFX *gfx)
{
  if (gfx) gfx->fillScreen(RGB565_BLACK);
}

void QuickSettingsView::update(Arduino_GFX *gfx)
{
  if (!gfx) return;
  uint8_t pct = (uint8_t)((_brightness / 255.0f) * 100.0f);
  char pctBuf[8];
  snprintf(pctBuf, sizeof(pctBuf), "%d%%", pct);
  ViewUtils::drawCenteredText(gfx, pctBuf, 90, 3, RGB565_GREEN);
}
