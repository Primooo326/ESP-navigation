#include "display/GC9A01Display.h"

GC9A01Display::GC9A01Display(uint8_t dc, uint8_t cs, uint8_t sclk, uint8_t mosi, int8_t rst, uint8_t bl, ITouchController *touch)
    : _pinDc(dc), _pinCs(cs), _pinSclk(sclk), _pinMosi(mosi), _pinRst(rst), _pinBl(bl),
      _bus(nullptr), _gfx(nullptr), _touchController(touch), _activeView(0), _lastTouchMillis(0),
      _sensorUiInitialized(false), _lastNeedleX(120), _lastNeedleY(45), _hasActiveNavigation(false)
{
}

GC9A01Display::~GC9A01Display()
{
  if (_gfx)
    delete _gfx;
  if (_bus)
    delete _bus;
}

bool GC9A01Display::begin()
{
  pinMode(_pinBl, OUTPUT);
  digitalWrite(_pinBl, HIGH);

  if (_touchController)
  {
    _touchController->begin();
  }

  _bus = new Arduino_ESP32SPI(_pinDc, _pinCs, _pinSclk, _pinMosi, GFX_NOT_DEFINED);
  _gfx = new Arduino_GC9A01(_bus, _pinRst, 0 /* rotación */, true /* IPS */);

  if (!_gfx->begin())
  {
    return false;
  }

  _gfx->fillScreen(RGB565_BLACK);
  return true;
}

void GC9A01Display::drawCenteredText(const String &text, int cy, uint8_t textSize, uint16_t textColor, uint16_t bgColor)
{
  if (!_gfx || text.length() == 0)
    return;

  _gfx->setTextSize(textSize);
  _gfx->setTextColor(textColor, bgColor);

  int16_t x1, y1;
  uint16_t w, h;
  _gfx->getTextBounds(text.c_str(), 0, 0, &x1, &y1, &w, &h);

  int cx = 120 - (w / 2);
  if (cx < 10)
    cx = 10;

  _gfx->setCursor(cx, cy);
  _gfx->print(text);
}

void GC9A01Display::update()
{
  if (!_gfx)
    return;

  uint32_t now = millis();

  // 1. Procesar Gestos Táctiles con CST816STouchController
  if (_touchController)
  {
    uint8_t gesture = 0;
    uint16_t x = 0, y = 0;
    if (_touchController->update(gesture, x, y))
    {
      _lastTouchMillis = now;
      Serial.printf(">> [Display] Gesto Táctil: 0x%02X en (%d, %d)\n", gesture, x, y);

      if (_showQuickSettings)
      {
        if (gesture == GESTURE_SWIPE_UP || (gesture == GESTURE_SINGLE_TAP && y < 60))
        {
          _showQuickSettings = false;
        }
        else if (gesture == GESTURE_SINGLE_TAP)
        {
          if (x < 110 && y >= 80 && y <= 160)
          {
            _brightnessLevel = (_brightnessLevel > 50) ? _brightnessLevel - 50 : 30;
            analogWrite(_pinBl, _brightnessLevel);
          }
          else if (x > 130 && y >= 80 && y <= 160)
          {
            _brightnessLevel = (_brightnessLevel < 205) ? _brightnessLevel + 50 : 255;
            analogWrite(_pinBl, _brightnessLevel);
          }
          else if (y > 160)
          {
            _rotation = (_rotation == 0) ? 2 : 0;
            _gfx->setRotation(_rotation);
          }
        }
        renderCurrentView();
        return;
      }

      switch (gesture)
      {
      case GESTURE_SWIPE_LEFT:
        _activeView = (_activeView + 1) % 4;
        break;
      case GESTURE_SWIPE_RIGHT:
        _activeView = (_activeView + 3) % 4;
        break;
      case GESTURE_SWIPE_DOWN:
        _showQuickSettings = true;
        break;
      case GESTURE_SWIPE_UP:
        _themeIndex = (_themeIndex + 1) % 3;
        break;
      case GESTURE_SINGLE_TAP:
        if (_activeView == 0 && _hasActiveNavigation)
        {
          _peekNextManeuver = !_peekNextManeuver;
        }
        else
        {
          _activeView = (_activeView + 1) % 4;
        }
        break;
      case GESTURE_LONG_PRESS:
        _peekNextManeuver = false;
        _showQuickSettings = false;
        _activeView = 0;
        break;
      }

      renderCurrentView();
    }
  }

  // 2. Temporizador Auto-Retorno (10 segundos) si hay navegación activa y el usuario está en otra vista
  if (_hasActiveNavigation && _activeView != 0 && !_showQuickSettings)
  {
    if (now - _lastTouchMillis > 10000)
    {
      _activeView = 0;
      _peekNextManeuver = false;
      renderCurrentView();
    }
  }
}

void GC9A01Display::renderCurrentView()
{
  if (!_gfx)
    return;

  if (_lastBleStatus.state != BLEState::CONNECTED)
  {
    renderDisconnectedUI(_lastBleStatus);
    return;
  }

  if (_showQuickSettings)
  {
    renderQuickSettingsOverlay();
    return;
  }

  switch (_activeView)
  {
  case 0:
    if (_hasActiveNavigation)
    {
      renderNavigationHUDUI(_lastNavData);
    }
    else
    {
      renderDashboardIdleUI(_lastNavData);
    }
    break;
  case 1:
    renderCompassRoseUI(_lastNavData);
    break;
  case 2:
    renderTripStatsUI(_lastNavData);
    break;
  case 3:
  default:
    renderDashboardIdleUI(_lastNavData);
    break;
  }
}

uint16_t GC9A01Display::getRingColor(BLEState state) const
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

String GC9A01Display::getStateText(BLEState state) const
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

void GC9A01Display::renderStatus(const BLEStatus &status)
{
  if (!_gfx)
    return;

  _lastBleStatus = status;
  renderCurrentView();
}

// ----------------------------------------------------------------------------
// INTERFAZ 1: ESPERANDO CONEXIÓN / DESCONECTADO (BLE Standby)
// ----------------------------------------------------------------------------
void GC9A01Display::renderDisconnectedUI(const BLEStatus &status)
{
  _gfx->fillCircle(120, 120, 119, RGB565_BLACK);
  _gfx->drawCircle(120, 120, 118, RGB565_DARKGREY);
  _gfx->drawCircle(120, 120, 117, RGB565_DARKGREY);

  // 1. Header Título
  drawCenteredText("SMART HUD", 35, 2, RGB565_WHITE);
  _gfx->drawFastHLine(45, 60, 150, RGB565_DARKGREY);

  // 2. Círculo concéntrico de escaneo BLE
  uint16_t statusColor = getRingColor(status.state);
  _gfx->drawCircle(120, 105, 28, statusColor);
  _gfx->drawCircle(120, 105, 14, statusColor);
  _gfx->fillCircle(120, 105, 5, statusColor);

  // 3. Texto de estado
  drawCenteredText(getStateText(status.state), 148, 2, statusColor);

  // 4. Subtexto nombre de dispositivo BLE
  String detailStr = (status.detail.length() > 0) ? status.detail : "ESP32C3_BLE";
  drawCenteredText(detailStr, 178, 1, RGB565_LIGHTGREY);
}

// ----------------------------------------------------------------------------
// INTERFAZ 2: RELOJ & CLIMA DASHBOARD (Shadcn Dark Mode Interface)
// ----------------------------------------------------------------------------
void GC9A01Display::renderDashboardIdleUI(const NavigationPacket &nav)
{
  _gfx->fillCircle(120, 120, 119, RGB565_BLACK);
  _gfx->drawCircle(120, 120, 118, RGB565_DARKGREY);
  _gfx->drawCircle(120, 120, 117, RGB565_DARKGREY);

  // 1. Header Top Badge: RELOJ & CLIMA / CONECTADO
  drawCenteredText("[ RELOJ & CLIMA ]", 25, 1, RGB565_CYAN);

  // 2. HORA DIGITAL GIGANTE HORA:MINUTO (Text size 4 Shadcn White)
  char clockBuf[10];
  snprintf(clockBuf, sizeof(clockBuf), "%02d:%02d", nav.currentHour, nav.currentMinute);
  drawCenteredText(clockBuf, 70, 4, RGB565_WHITE);

  // 3. SECCIÓN CLIMA - Widget Shadcn Amber & White
  drawCenteredText("21 C  DESPEJADO", 122, 2, RGB565_YELLOW);

  // 4. Rumbo / Brújula central secundaria (Zinc / Lightgrey)
  char headingBuf[24];
  snprintf(headingBuf, sizeof(headingBuf), "%3d deg  RUMBO", nav.headingDeg % 360);
  drawCenteredText(headingBuf, 158, 1, RGB565_LIGHTGREY);

  // 5. Footer: Estado o aviso de auto-retorno
  if (_hasActiveNavigation)
  {
    drawCenteredText("NAVEGACION ACTIVA (8s)", 188, 1, RGB565_LIGHTGREY);
  }
  else
  {
    drawCenteredText("SIN NAVEGACION ACTIVA", 188, 1, RGB565_LIGHTGREY);
  }
}

// ----------------------------------------------------------------------------
// INTERFAZ 3: NAVEGACIÓN TBT ACTIVA (Smart HUD con Flechas y Metros OSRM)
// ----------------------------------------------------------------------------
void GC9A01Display::renderNavigationHUDUI(const NavigationPacket &nav)
{
  _gfx->fillCircle(120, 120, 119, RGB565_BLACK);
  _gfx->drawCircle(120, 120, 118, RGB565_DARKGREY);
  _gfx->drawCircle(120, 120, 117, RGB565_DARKGREY);

  // 1. Icono de maniobra central GIGANTE y centrado (cy = 55)
  drawTurnArrow(nav.turnIcon, 120, 55, RGB565_WHITE);

  // 2. Distancia al siguiente giro en gran formato (Shadcn Bold White)
  char distBuf[16];
  if (nav.distanceMeters >= 1000)
  {
    snprintf(distBuf, sizeof(distBuf), "%.1f km", nav.distanceMeters / 1000.0f);
  }
  else
  {
    snprintf(distBuf, sizeof(distBuf), "%d m", nav.distanceMeters);
  }
  drawCenteredText(distBuf, 106, 3, RGB565_WHITE);

  // 3. Metros restantes del viaje completo OSRM (Shadcn Zinc sutil)
  char totalBuf[24];
  if (nav.totalRemainingMeters >= 1000)
  {
    snprintf(totalBuf, sizeof(totalBuf), "Restan: %.1f km", nav.totalRemainingMeters / 1000.0f);
  }
  else
  {
    snprintf(totalBuf, sizeof(totalBuf), "Restan: %d m", nav.totalRemainingMeters);
  }
  drawCenteredText(totalBuf, 136, 1, RGB565_LIGHTGREY);

  // 4. Nombre de la calle (Shadcn White)
  char streetBuf[16];
  snprintf(streetBuf, sizeof(streetBuf), "%-14s", nav.streetName);
  drawCenteredText(streetBuf, 160, 2, RGB565_WHITE);

  // 5. Badge de velocidad (Shadcn Amber / Yellow)
  char speedBuf[16];
  snprintf(speedBuf, sizeof(speedBuf), "%3d km/h", nav.speedKmh);
  drawCenteredText(speedBuf, 190, 2, RGB565_YELLOW);
}

void GC9A01Display::renderNavigationData(const NavigationPacket &navData)
{
  if (!_gfx)
    return;

  _lastNavData = navData;

  if (navData.navState == 1 || navData.navState == 2)
  {
    _hasActiveNavigation = true;
  }
  else
  {
    _hasActiveNavigation = false;
  }

  renderCurrentView();
}

void GC9A01Display::drawStaticSensorUI()
{
  _gfx->fillScreen(RGB565_BLACK);
  _gfx->drawCircle(120, 120, 118, RGB565_DARKGREY);
  _gfx->drawCircle(120, 120, 117, RGB565_DARKGREY);
  _gfx->drawCircle(120, 120, 95, RGB565_DARKGREY);

  drawCenteredText("N", 26, 1, RGB565_WHITE);
  drawCenteredText("S", 206, 1, RGB565_LIGHTGREY);

  _gfx->setTextColor(RGB565_LIGHTGREY);
  _gfx->setCursor(206, 117);
  _gfx->print("E");
  _gfx->setCursor(26, 117);
  _gfx->print("O");

  _lastNeedleX = 120;
  _lastNeedleY = 45;
  _sensorUiInitialized = true;
}

void GC9A01Display::renderSensorData(const SensorData &data)
{
  if (!_gfx)
    return;

  if (!_sensorUiInitialized)
  {
    drawStaticSensorUI();
  }

  float headingAngle = 360.0f - data.heading;
  float rad = (headingAngle - 90.0f) * (M_PI / 180.0f);

  int newNeedleX = 120 + (int)(cos(rad) * 70.0f);
  int newNeedleY = 120 + (int)(sin(rad) * 70.0f);

  if (newNeedleX != _lastNeedleX || newNeedleY != _lastNeedleY)
  {
    _gfx->drawLine(120, 120, _lastNeedleX, _lastNeedleY, RGB565_BLACK);
    _gfx->fillCircle(_lastNeedleX, _lastNeedleY, 4, RGB565_BLACK);

    _gfx->drawLine(120, 120, newNeedleX, newNeedleY, RGB565_WHITE);
    _gfx->fillCircle(newNeedleX, newNeedleY, 4, RGB565_WHITE);

    _lastNeedleX = newNeedleX;
    _lastNeedleY = newNeedleY;
  }

  char headingBuf[16];
  int headingInt = (int)data.heading % 360;
  if (headingInt < 0) headingInt += 360;
  snprintf(headingBuf, sizeof(headingBuf), "H: %3d deg", headingInt);
  drawCenteredText(headingBuf, 45, 2, RGB565_WHITE);
}

void GC9A01Display::drawTurnArrow(uint8_t turnIcon, int cx, int cy, uint16_t color)
{
  _gfx->fillRect(cx - 35, cy - 35, 70, 70, RGB565_BLACK);

  switch (turnIcon)
  {
  case 1: // STRAIGHT
    _gfx->fillTriangle(cx, cy - 30, cx - 20, cy - 6, cx + 20, cy - 6, color);
    _gfx->fillRect(cx - 7, cy - 6, 14, 32, color);
    break;

  case 2: // TURN RIGHT (Giro 90° Derecha)
    _gfx->fillRect(cx - 18, cy - 4, 14, 30, color);
    _gfx->fillRect(cx - 18, cy - 16, 26, 14, color);
    _gfx->fillRect(cx - 4, cy - 16, 22, 14, color);
    _gfx->fillTriangle(cx + 30, cy - 9, cx + 12, cy - 26, cx + 12, cy + 8, color);
    break;

  case 3: // TURN LEFT (Giro 90° Izquierda)
    _gfx->fillRect(cx + 4, cy - 4, 14, 30, color);
    _gfx->fillRect(cx - 8, cy - 16, 26, 14, color);
    _gfx->fillRect(cx - 18, cy - 16, 22, 14, color);
    _gfx->fillTriangle(cx - 30, cy - 9, cx - 12, cy - 26, cx - 12, cy + 8, color);
    break;

  case 4: // SLIGHT RIGHT (Giro Suave Derecha 45°)
    _gfx->fillRect(cx - 14, cy, 14, 26, color);
    _gfx->fillTriangle(cx - 14, cy + 6, cx + 12, cy - 18, cx - 4, cy + 16, color);
    _gfx->fillTriangle(cx + 26, cy - 26, cx + 4, cy - 24, cx + 24, cy - 4, color);
    break;

  case 5: // SLIGHT LEFT (Giro Suave Izquierda 45°)
    _gfx->fillRect(cx + 0, cy, 14, 26, color);
    _gfx->fillTriangle(cx + 14, cy + 6, cx - 12, cy - 18, cx + 4, cy + 16, color);
    _gfx->fillTriangle(cx - 26, cy - 26, cx - 4, cy - 24, cx - 24, cy - 4, color);
    break;

  case 6: // SHARP RIGHT (Giro Pronunciado Derecha)
    _gfx->fillRect(cx - 18, cy - 10, 14, 34, color);
    _gfx->fillRect(cx - 18, cy - 24, 36, 14, color);
    _gfx->fillRect(cx + 4, cy - 12, 14, 20, color);
    _gfx->fillTriangle(cx + 11, cy + 18, cx - 4, cy, cx + 26, cy, color);
    break;

  case 7: // SHARP LEFT (Giro Pronunciado Izquierda)
    _gfx->fillRect(cx + 4, cy - 10, 14, 34, color);
    _gfx->fillRect(cx - 18, cy - 24, 36, 14, color);
    _gfx->fillRect(cx - 18, cy - 12, 14, 20, color);
    _gfx->fillTriangle(cx - 11, cy + 18, cx + 4, cy, cx - 26, cy, color);
    break;

  case 8: // ROUNDABOUT (Rotonda)
    _gfx->drawCircle(cx, cy, 22, color);
    _gfx->drawCircle(cx, cy, 21, color);
    _gfx->drawCircle(cx, cy, 20, color);
    _gfx->fillTriangle(cx + 26, cy - 14, cx + 8, cy - 26, cx + 14, cy - 2, color);
    break;

  case 9: // ARRIVED (Destino)
    _gfx->fillCircle(cx, cy, 22, RGB565_WHITE);
    _gfx->fillCircle(cx, cy, 14, RGB565_BLACK);
    _gfx->fillCircle(cx, cy, 6, RGB565_GREEN);
    break;

  default: // NONE / DEFAULT (Recto)
    _gfx->fillTriangle(cx, cy - 30, cx - 20, cy - 6, cx + 20, cy - 6, color);
    _gfx->fillRect(cx - 7, cy - 6, 14, 32, color);
    break;
  }
}

// ----------------------------------------------------------------------------
// INTERFAZ 4: BRÚJULA DIGITAL COMPACTA (Rose Vectorial)
// ----------------------------------------------------------------------------
void GC9A01Display::renderCompassRoseUI(const NavigationPacket &nav)
{
  uint16_t mainColor = (_themeIndex == 0) ? RGB565_GREEN : ((_themeIndex == 1) ? RGB565_WHITE : RGB565_CYAN);

  _gfx->fillCircle(120, 120, 119, RGB565_BLACK);
  _gfx->drawCircle(120, 120, 118, RGB565_DARKGREY);
  _gfx->drawCircle(120, 120, 95, RGB565_DARKGREY);

  drawCenteredText("[ BRUJULA DIGITAL ]", 25, 1, mainColor);

  drawCenteredText("N", 38, 1, mainColor);
  drawCenteredText("S", 192, 1, RGB565_LIGHTGREY);

  float headingAngle = 360.0f - nav.headingDeg;
  float rad = (headingAngle - 90.0f) * (M_PI / 180.0f);

  int needleX = 120 + (int)(cos(rad) * 65.0f);
  int needleY = 120 + (int)(sin(rad) * 65.0f);

  _gfx->drawLine(120, 120, needleX, needleY, mainColor);
  _gfx->fillCircle(needleX, needleY, 5, mainColor);
  _gfx->fillCircle(120, 120, 4, RGB565_WHITE);

  char degBuf[20];
  snprintf(degBuf, sizeof(degBuf), "%3d deg", nav.headingDeg % 360);
  drawCenteredText(degBuf, 110, 2, RGB565_WHITE);

  char distBuf[24];
  snprintf(distBuf, sizeof(distBuf), "Restan: %.1f km", nav.totalRemainingMeters / 1000.0f);
  drawCenteredText(distBuf, 155, 1, RGB565_LIGHTGREY);
  drawCenteredText("1/4  Desliza Lateral", 188, 1, RGB565_DARKGREY);
}

// ----------------------------------------------------------------------------
// INTERFAZ 5: ESTADÍSTICAS DEL VIAJE & METRICAS
// ----------------------------------------------------------------------------
void GC9A01Display::renderTripStatsUI(const NavigationPacket &nav)
{
  uint16_t mainColor = (_themeIndex == 0) ? RGB565_GREEN : ((_themeIndex == 1) ? RGB565_WHITE : RGB565_CYAN);

  _gfx->fillCircle(120, 120, 119, RGB565_BLACK);
  _gfx->drawCircle(120, 120, 118, RGB565_DARKGREY);

  drawCenteredText("[ PANEL DE VIAJE ]", 25, 1, mainColor);

  char speedBuf[20];
  snprintf(speedBuf, sizeof(speedBuf), "%d", nav.speedKmh);
  drawCenteredText(speedBuf, 60, 4, RGB565_WHITE);
  drawCenteredText("KM / H", 100, 1, RGB565_YELLOW);

  char totalBuf[24];
  if (nav.totalRemainingMeters >= 1000)
    snprintf(totalBuf, sizeof(totalBuf), "Restante: %.1f km", nav.totalRemainingMeters / 1000.0f);
  else
    snprintf(totalBuf, sizeof(totalBuf), "Restante: %d m", nav.totalRemainingMeters);

  drawCenteredText(totalBuf, 128, 2, RGB565_WHITE);

  char headingBuf[20];
  snprintf(headingBuf, sizeof(headingBuf), "Rumbo: %d deg", nav.headingDeg);
  drawCenteredText(headingBuf, 160, 1, RGB565_LIGHTGREY);

  drawCenteredText("2/4  Desliza Lateral", 188, 1, RGB565_DARKGREY);
}

// ----------------------------------------------------------------------------
// INTERFAZ 6: MENÚ DE CONTROL RÁPIDO / CORTINILLA (Swipe Down Overlay)
// ----------------------------------------------------------------------------
void GC9A01Display::renderQuickSettingsOverlay()
{
  _gfx->fillCircle(120, 120, 119, RGB565_BLACK);
  _gfx->drawCircle(120, 120, 118, RGB565_YELLOW);
  _gfx->drawCircle(120, 120, 117, RGB565_YELLOW);

  drawCenteredText("[ CORTINILLA CONTROL ]", 25, 1, RGB565_YELLOW);
  _gfx->drawFastHLine(30, 42, 180, RGB565_DARKGREY);

  drawCenteredText("BRILLO PANTALLA", 52, 1, RGB565_WHITE);

  // Botones de Brillo - / +
  _gfx->fillRoundRect(35, 75, 45, 45, 8, RGB565_DARKGREY);
  drawCenteredText("-", 88, 3, RGB565_WHITE);

  uint8_t pct = (uint8_t)((_brightnessLevel / 255.0f) * 100.0f);
  char pctBuf[8];
  snprintf(pctBuf, sizeof(pctBuf), "%d%%", pct);
  drawCenteredText(pctBuf, 90, 2, RGB565_GREEN);

  _gfx->fillRoundRect(160, 75, 45, 45, 8, RGB565_DARKGREY);
  drawCenteredText("+", 88, 3, RGB565_WHITE);

  // Botón Rotación Pantalla
  _gfx->fillRoundRect(45, 140, 150, 36, 10, RGB565_NAVY);
  char rotBuf[24];
  snprintf(rotBuf, sizeof(rotBuf), "ROTAR: %d DEG", _rotation * 90);
  drawCenteredText(rotBuf, 150, 1, RGB565_WHITE);

  drawCenteredText("Arriba: Cerrar", 192, 1, RGB565_LIGHTGREY);
}
