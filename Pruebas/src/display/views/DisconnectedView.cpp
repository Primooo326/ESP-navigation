#include "display/views/DisconnectedView.h"
#include "display/views/ViewUtils.h"

uint16_t DisconnectedView::getRingColor(BLEState state) const
{
  switch (state)
  {
  case BLEState::INIT:
    return RGB565_YELLOW;
  case BLEState::ADVERTISING:
    return RGB565_CYAN;
  case BLEState::CONNECTED:
    return RGB565_GREEN;
  case BLEState::DISCONNECTED:
    return RGB565_RED;
  default:
    return RGB565_WHITE;
  }
}

String DisconnectedView::getStateText(BLEState state) const
{
  switch (state)
  {
  case BLEState::INIT:
    return "INICIANDO BLE";
  case BLEState::ADVERTISING:
    return "ESPERANDO BLE";
  case BLEState::CONNECTED:
    return "CONECTADO";
  case BLEState::DISCONNECTED:
    return "DESCONECTADO";
  default:
    return "STANDBY";
  }
}

void DisconnectedView::onEnter(Arduino_GFX *gfx)
{
  if (!gfx)
    return;
  gfx->fillScreen(RGB565_BLACK);
  gfx->drawCircle(120, 120, 118, RGB565_DARKGREY);
  gfx->drawCircle(120, 120, 117, RGB565_DARKGREY);
  renderStatus(gfx, _lastStatus);
}

void DisconnectedView::onExit(Arduino_GFX *gfx)
{
  if (gfx)
    gfx->fillScreen(RGB565_BLACK);
}

void DisconnectedView::renderStatus(Arduino_GFX *gfx, const BLEStatus &status)
{
  if (!gfx)
    return;

  _lastStatus = status;

  ViewUtils::drawCenteredText(gfx, "SMART HUD", 35, 2, RGB565_WHITE);
  gfx->drawFastHLine(45, 60, 150, RGB565_DARKGREY);

  uint16_t statusColor = getRingColor(status.state);
  gfx->drawCircle(120, 105, 28, statusColor);
  gfx->drawCircle(120, 105, 14, statusColor);
  gfx->fillCircle(120, 105, 5, statusColor);

  ViewUtils::drawCenteredText(gfx, getStateText(status.state), 148, 2, statusColor);

  String detailStr = (status.detail.length() > 0) ? status.detail : "ESP32C3_BLE";
  ViewUtils::drawCenteredText(gfx, detailStr, 178, 1, RGB565_LIGHTGREY);
}
