#include "display/GC9A01Display.h"

GC9A01Display::GC9A01Display(uint8_t dc, uint8_t cs, uint8_t sclk, uint8_t mosi, int8_t rst, uint8_t bl)
    : _pinDc(dc), _pinCs(cs), _pinSclk(sclk), _pinMosi(mosi), _pinRst(rst), _pinBl(bl),
      _bus(nullptr), _gfx(nullptr), _activeView(0), _lastTouchMillis(0), _lastTouchHandledMillis(0),
      _touchInitialized(false), _sensorUiInitialized(false),
      _lastNeedleX(120), _lastNeedleY(45), _lastBubbleX(120), _lastBubbleY(120),
      _hasActiveNavigation(false)
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

  // Inicializar I2C para pantalla táctil CST816S (SDA = GPIO 4, SCL = GPIO 5)
  Wire.begin(4, 5);

  _bus = new Arduino_ESP32SPI(_pinDc, _pinCs, _pinSclk, _pinMosi, GFX_NOT_DEFINED);
  _gfx = new Arduino_GC9A01(_bus, _pinRst, 0 /* rotación */, true /* IPS */);

  if (!_gfx->begin())
  {
    return false;
  }

  _gfx->fillScreen(RGB565_BLACK);
  return true;
}

bool GC9A01Display::readCST816STouch(uint8_t &gesture, uint16_t &x, uint16_t &y)
{
  Wire.beginTransmission(0x15);
  Wire.write(0x01);
  if (Wire.endTransmission(false) != 0)
  {
    return false;
  }

  uint8_t bytesRead = Wire.requestFrom((uint8_t)0x15, (uint8_t)6);
  if (bytesRead < 6)
  {
    return false;
  }

  gesture = Wire.read();        // Reg 0x01: Gesture ID
  uint8_t points = Wire.read();  // Reg 0x02: Finger count
  uint8_t xHigh = Wire.read();   // Reg 0x03
  uint8_t xLow = Wire.read();    // Reg 0x04
  uint8_t yHigh = Wire.read();   // Reg 0x05
  uint8_t yLow = Wire.read();    // Reg 0x06

  x = ((xHigh & 0x0F) << 8) | xLow;
  y = ((yHigh & 0x0F) << 8) | yLow;

  bool isCurrentlyTouched = (points == 1 && x < 240 && y < 240);

  static bool wasTouchedPrev = false;

  if (isCurrentlyTouched && !wasTouchedPrev)
  {
    wasTouchedPrev = true;
    return true; // Evento único de toque al presionar (Edge Detection)
  }

  if (!isCurrentlyTouched)
  {
    wasTouchedPrev = false;
  }

  return false;
}

void GC9A01Display::update()
{
  if (!_gfx)
    return;

  uint32_t now = millis();

  // 1. Polling Touch CST816S
  uint8_t gesture = 0;
  uint16_t x = 0, y = 0;
  if (readCST816STouch(gesture, x, y))
  {
    if (now - _lastTouchHandledMillis > 300) // Debounce 300ms
    {
      _lastTouchHandledMillis = now;
      _lastTouchMillis = now;

      // Toggle vista entre Navigation HUD (0) y Reloj/Clima Dashboard (1)
      _activeView = (_activeView == 0) ? 1 : 0;
      Serial.printf(">> [Touch CST816S] Toque detectado (X:%d, Y:%d, G:%d)! Cambiando vista a: %d\n", x, y, gesture, _activeView);
      renderCurrentView();
    }
  }

  // 2. Temporizador Auto-Retorno (8 segundos) si hay navegación activa y estamos en Vista 1 (Reloj)
  if (_hasActiveNavigation && _activeView == 1)
  {
    if (now - _lastTouchMillis > 8000)
    {
      _activeView = 0;
      Serial.println(">> [Touch] Timeout 8s expiro. Volviendo a Vista 0 (Navegacion HUD).");
      renderCurrentView();
    }
  }
}

void GC9A01Display::renderCurrentView()
{
  if (_lastBleStatus.state != BLEState::CONNECTED)
  {
    renderDisconnectedUI(_lastBleStatus);
    return;
  }

  if (_activeView == 1)
  {
    renderDashboardIdleUI(_lastNavData);
  }
  else
  {
    if (_hasActiveNavigation)
    {
      renderNavigationHUDUI(_lastNavData);
    }
    else
    {
      renderDashboardIdleUI(_lastNavData);
    }
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

  // Anillo de borde sutil Shadcn (#27272A)
  _gfx->drawCircle(120, 120, 118, RGB565_DARKGREY);
  _gfx->drawCircle(120, 120, 117, RGB565_DARKGREY);

  // Header Titulo
  _gfx->setTextColor(RGB565_WHITE, RGB565_BLACK);
  _gfx->setTextSize(2);
  _gfx->setCursor(55, 38);
  _gfx->print("SMART HUD");

  _gfx->drawFastHLine(45, 62, 150, RGB565_DARKGREY);

  // Círculo concéntrico sutil de escaneo BLE
  uint16_t statusColor = getRingColor(status.state);
  _gfx->drawCircle(120, 108, 28, statusColor);
  _gfx->drawCircle(120, 108, 14, statusColor);
  _gfx->fillCircle(120, 108, 5, statusColor);

  // Texto de estado
  String stateStr = getStateText(status.state);
  _gfx->setTextColor(statusColor, RGB565_BLACK);
  _gfx->setTextSize(2);
  int16_t xPos = 120 - (stateStr.length() * 6);
  if (xPos < 20) xPos = 20;
  _gfx->setCursor(xPos, 152);
  _gfx->print(stateStr);

  // Subtexto nombre de dispositivo BLE
  _gfx->setTextColor(RGB565_LIGHTGREY, RGB565_BLACK);
  _gfx->setTextSize(1);
  String detailStr = (status.detail.length() > 0) ? status.detail : "ESP32C3_BLE";
  int16_t detailX = 120 - (detailStr.length() * 3);
  if (detailX < 15) detailX = 15;
  _gfx->setCursor(detailX, 180);
  _gfx->print(detailStr);
}

// ----------------------------------------------------------------------------
// INTERFAZ 2: RELOJ & CLIMA DASHBOARD (Shadcn Dark Mode Interface)
// ----------------------------------------------------------------------------
void GC9A01Display::renderDashboardIdleUI(const NavigationPacket &nav)
{
  _gfx->fillCircle(120, 120, 119, RGB565_BLACK);

  // Anillo de borde en Slate/Zinc sutil (#27272A)
  _gfx->drawCircle(120, 120, 118, RGB565_DARKGREY);
  _gfx->drawCircle(120, 120, 117, RGB565_DARKGREY);

  // 1. Header Top Badge: RELOJ & CLIMA / CONECTADO
  _gfx->setTextColor(RGB565_CYAN, RGB565_BLACK);
  _gfx->setTextSize(1);
  _gfx->setCursor(62, 24);
  _gfx->print("[ RELOJ & CLIMA ]");

  // 2. HORA DIGITAL GIGANTE HORA:MINUTO (Text size 4 Shadcn White)
  _gfx->setTextColor(RGB565_WHITE, RGB565_BLACK);
  _gfx->setTextSize(4);
  char clockBuf[10];
  snprintf(clockBuf, sizeof(clockBuf), "%02d:%02d", nav.currentHour, nav.currentMinute);
  int clockX = 120 - (strlen(clockBuf) * 12);
  _gfx->setCursor(clockX, 75);
  _gfx->print(clockBuf);

  // 3. SECCIÓN CLIMA - Widget Shadcn Amber & White
  _gfx->setTextColor(RGB565_YELLOW, RGB565_BLACK);
  _gfx->setTextSize(2);
  _gfx->setCursor(55, 125);
  _gfx->print("21 C"); // Temperatura
  _gfx->setTextColor(RGB565_WHITE, RGB565_BLACK);
  _gfx->setCursor(120, 125);
  _gfx->print("DESPEJADO"); // Estado Clima

  // 4. Rumbo / Brújula central secundaria (Zinc / Lightgrey)
  _gfx->setTextColor(RGB565_LIGHTGREY, RGB565_BLACK);
  _gfx->setTextSize(1);
  _gfx->setCursor(72, 160);
  _gfx->printf("%3d deg  RUMBO", nav.headingDeg % 360);

  // 5. Footer: Estado o aviso de auto-retorno
  _gfx->setTextColor(RGB565_LIGHTGREY, RGB565_BLACK);
  _gfx->setTextSize(1);
  if (_hasActiveNavigation)
  {
    _gfx->setCursor(35, 190);
    _gfx->print("NAVEGACION ACTIVA (8s)");
  }
  else
  {
    _gfx->setCursor(45, 190);
    _gfx->print("SIN NAVEGACION ACTIVA");
  }
}

// ----------------------------------------------------------------------------
// INTERFAZ 3: NAVEGACIÓN TBT ACTIVA (Smart HUD con Flechas y Metros OSRM)
// ----------------------------------------------------------------------------
void GC9A01Display::renderNavigationHUDUI(const NavigationPacket &nav)
{
  _gfx->fillCircle(120, 120, 119, RGB565_BLACK);

  // Anillos exteriores en Zinc/Slate sutil (#27272A)
  _gfx->drawCircle(120, 120, 118, RGB565_DARKGREY);
  _gfx->drawCircle(120, 120, 117, RGB565_DARKGREY);

  // 1. Icono de maniobra central GIGANTE y centrado (sin reloj top)
  drawTurnArrow(nav.turnIcon, 120, 55, RGB565_WHITE);

  // 2. Distancia al siguiente giro en gran formato (Shadcn Bold White)
  _gfx->setTextColor(RGB565_WHITE, RGB565_BLACK);
  _gfx->setTextSize(3);
  char distBuf[16];
  if (nav.distanceMeters >= 1000)
  {
    snprintf(distBuf, sizeof(distBuf), "%.1f km", nav.distanceMeters / 1000.0f);
  }
  else
  {
    snprintf(distBuf, sizeof(distBuf), "%d m", nav.distanceMeters);
  }

  int distLen = strlen(distBuf);
  int distX = 120 - (distLen * 9);
  if (distX < 20) distX = 20;
  _gfx->setCursor(distX, 108);
  _gfx->print(distBuf);

  // 3. Metros restantes del viaje completo OSRM (Shadcn Zinc sutil)
  _gfx->setTextColor(RGB565_LIGHTGREY, RGB565_BLACK);
  _gfx->setTextSize(1);
  char totalBuf[24];
  if (nav.totalRemainingMeters >= 1000)
  {
    snprintf(totalBuf, sizeof(totalBuf), "Restan: %.1f km", nav.totalRemainingMeters / 1000.0f);
  }
  else
  {
    snprintf(totalBuf, sizeof(totalBuf), "Restan: %d m", nav.totalRemainingMeters);
  }
  int totalLen = strlen(totalBuf);
  int totalX = 120 - (totalLen * 3);
  if (totalX < 15) totalX = 15;
  _gfx->setCursor(totalX, 138);
  _gfx->print(totalBuf);

  // 4. Nombre de la calle (Shadcn White)
  _gfx->setTextColor(RGB565_WHITE, RGB565_BLACK);
  _gfx->setTextSize(2);
  int streetLen = strlen(nav.streetName);
  int streetX = 120 - (streetLen * 6);
  if (streetX < 20) streetX = 20;
  _gfx->setCursor(streetX, 160);
  _gfx->printf("%-14s", nav.streetName);

  // 5. Badge de velocidad (Shadcn Amber / Yellow)
  _gfx->setTextColor(RGB565_YELLOW, RGB565_BLACK);
  _gfx->setTextSize(2);
  _gfx->setCursor(68, 192);
  _gfx->printf("%3d km/h", nav.speedKmh);
}

void GC9A01Display::renderNavigationData(const NavigationPacket &navData)
{
  if (!_gfx)
    return;

  _lastNavData = navData;

  // navState: 1 = Navegación Activa, 2 = Llegado al Destino
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

  _gfx->setTextColor(RGB565_WHITE);
  _gfx->setTextSize(1);
  _gfx->setCursor(117, 26);
  _gfx->print("N");
  _gfx->setTextColor(RGB565_LIGHTGREY);
  _gfx->setCursor(117, 206);
  _gfx->print("S");
  _gfx->setCursor(206, 117);
  _gfx->print("E");
  _gfx->setCursor(26, 117);
  _gfx->print("O");

  _lastNeedleX = 120;
  _lastNeedleY = 45;
  _lastBubbleX = 120;
  _lastBubbleY = 120;
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

  _gfx->setTextColor(RGB565_WHITE, RGB565_BLACK);
  _gfx->setTextSize(2);
  _gfx->setCursor(70, 45);
  int headingInt = (int)data.heading % 360;
  if (headingInt < 0) headingInt += 360;
  _gfx->printf("H: %3d%c", headingInt, 247);
}

void GC9A01Display::drawTurnArrow(uint8_t turnIcon, int cx, int cy, uint16_t color)
{
  // Limpiar área de flecha (box 70x70) en fondo Shadcn Negro
  _gfx->fillRect(cx - 35, cy - 35, 70, 70, RGB565_BLACK);

  switch (turnIcon)
  {
  case 1: // STRAIGHT (Recto Shadcn Icon)
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

