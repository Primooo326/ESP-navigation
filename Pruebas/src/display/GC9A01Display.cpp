#include "display/GC9A01Display.h"

GC9A01Display::GC9A01Display(uint8_t dc, uint8_t cs, uint8_t sclk, uint8_t mosi, int8_t rst, uint8_t bl)
    : _pinDc(dc), _pinCs(cs), _pinSclk(sclk), _pinMosi(mosi), _pinRst(rst), _pinBl(bl),
      _bus(nullptr), _gfx(nullptr), _sensorUiInitialized(false),
      _lastNeedleX(120), _lastNeedleY(45), _lastBubbleX(120), _lastBubbleY(120)
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

  _bus = new Arduino_ESP32SPI(_pinDc, _pinCs, _pinSclk, _pinMosi, GFX_NOT_DEFINED);
  _gfx = new Arduino_GC9A01(_bus, _pinRst, 0 /* rotación */, true /* IPS */);

  if (!_gfx->begin())
  {
    return false;
  }

  _gfx->fillScreen(RGB565_BLACK);
  return true;
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
    return "ANUNCIANDO...";
  case BLEState::CONNECTED:
    return "CONECTADO!";
  case BLEState::DISCONNECTED:
    return "DESCONECTADO";
  default:
    return "DESCONOCIDO";
  }
}

void GC9A01Display::renderStatus(const BLEStatus &status)
{
  if (!_gfx)
    return;

  // Reiniciar estado de la UI de sensores si cambiamos de estado de conexión
  _sensorUiInitialized = false;

  uint16_t ringColor = getRingColor(status.state);
  String stateStr = getStateText(status.state);

  _gfx->fillCircle(120, 120, 112, RGB565_BLACK);

  _gfx->drawCircle(120, 120, 118, ringColor);
  _gfx->drawCircle(120, 120, 117, ringColor);
  _gfx->drawCircle(120, 120, 116, ringColor);

  _gfx->setTextColor(RGB565_LIGHTGREY);
  _gfx->setTextSize(2);
  _gfx->setCursor(48, 60);
  _gfx->println("ESP32-C3 BLE");

  _gfx->drawFastHLine(40, 85, 160, RGB565_DARKGREY);

  _gfx->setTextColor(ringColor);
  _gfx->setTextSize(2);
  int16_t xPos = 120 - (stateStr.length() * 6);
  if (xPos < 20)
    xPos = 20;
  _gfx->setCursor(xPos, 105);
  _gfx->println(stateStr);

  if (status.detail.length() > 0)
  {
    _gfx->setTextColor(RGB565_WHITE);
    _gfx->setTextSize(1);
    int16_t detailX = 120 - (status.detail.length() * 3);
    if (detailX < 15)
      detailX = 15;
    _gfx->setCursor(detailX, 140);
    _gfx->println(status.detail);
  }

  if (status.state == BLEState::CONNECTED)
  {
    _gfx->setTextColor(RGB565_GREEN);
    _gfx->setTextSize(1);
    _gfx->setCursor(80, 165);
    _gfx->print("Android Unido");
  }
  else if (status.state == BLEState::ADVERTISING)
  {
    _gfx->setTextColor(RGB565_YELLOW);
    _gfx->setTextSize(1);
    _gfx->setCursor(55, 165);
    _gfx->print("Visible en Android");
  }
}

void GC9A01Display::drawStaticSensorUI()
{
  _gfx->fillScreen(RGB565_BLACK);

  // Anillos exteriores verdes
  _gfx->drawCircle(120, 120, 118, RGB565_GREEN);
  _gfx->drawCircle(120, 120, 117, RGB565_GREEN);

  // Rosa de los vientos circular
  _gfx->drawCircle(120, 120, 95, RGB565_DARKGREY);

  // Puntos cardinales
  _gfx->setTextColor(RGB565_RED);
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

  // Círculo del nivel de burbuja
  _gfx->drawCircle(120, 120, 25, RGB565_BLUE);

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

  // --------------------------------------------------------------------------
  // 1. BRÚJULA (Corrección de Inversión y Renderizado Diferencial Anti-Parpadeo)
  // --------------------------------------------------------------------------
  // Invertir ángulo (360 - heading) para orientar el Norte correctamente
  float headingAngle = 360.0f - data.heading;
  float rad = (headingAngle - 90.0f) * (M_PI / 180.0f);

  int newNeedleX = 120 + (int)(cos(rad) * 70.0f);
  int newNeedleY = 120 + (int)(sin(rad) * 70.0f);

  if (newNeedleX != _lastNeedleX || newNeedleY != _lastNeedleY)
  {
    // Borrar únicamente la aguja anterior (sin refrescar toda la pantalla)
    _gfx->drawLine(120, 120, _lastNeedleX, _lastNeedleY, RGB565_BLACK);
    _gfx->fillCircle(_lastNeedleX, _lastNeedleY, 4, RGB565_BLACK);

    // Redibujar círculo central por si la aguja previa lo cruzó
    _gfx->drawCircle(120, 120, 25, RGB565_BLUE);

    // Dibujar nueva aguja en Rojo
    _gfx->drawLine(120, 120, newNeedleX, newNeedleY, RGB565_RED);
    _gfx->fillCircle(newNeedleX, newNeedleY, 4, RGB565_RED);
    _gfx->fillCircle(120, 120, 4, RGB565_WHITE);

    _lastNeedleX = newNeedleX;
    _lastNeedleY = newNeedleY;
  }

  // --------------------------------------------------------------------------
  // 2. NIVEL DE BURBUJA (Acelerómetro X/Y Diferencial)
  // --------------------------------------------------------------------------
  int newBubbleX = 120 + (int)(data.accX * 2.5f);
  int newBubbleY = 120 + (int)(data.accY * 2.5f);

  if (newBubbleX < 98)
    newBubbleX = 98;
  if (newBubbleX > 142)
    newBubbleX = 142;
  if (newBubbleY < 98)
    newBubbleY = 98;
  if (newBubbleY > 142)
    newBubbleY = 142;

  if (newBubbleX != _lastBubbleX || newBubbleY != _lastBubbleY)
  {
    // Borrar únicamente la burbuja anterior
    _gfx->fillCircle(_lastBubbleX, _lastBubbleY, 3, RGB565_BLACK);

    // Redibujar línea de la aguja si pasaba por esa zona
    _gfx->drawLine(120, 120, _lastNeedleX, _lastNeedleY, RGB565_RED);

    // Dibujar burbuja nueva
    _gfx->fillCircle(newBubbleX, newBubbleY, 3, RGB565_YELLOW);

    _lastBubbleX = newBubbleX;
    _lastBubbleY = newBubbleY;
  }

  // --------------------------------------------------------------------------
  // 3. ACTUALIZACIÓN DE TEXTO SOBREESCRIBIENDO FONDO (Anti-Parpadeo)
  // --------------------------------------------------------------------------
  _gfx->setTextColor(RGB565_CYAN, RGB565_BLACK); // Fondo negro evita borrado de pantalla
  _gfx->setTextSize(2);
  _gfx->setCursor(70, 45);
  int headingInt = (int)data.heading % 360;
  if (headingInt < 0)
    headingInt += 360;

  if (headingInt < 10)
    _gfx->printf("H:   %d%c", headingInt, 247);
  else if (headingInt < 100)
    _gfx->printf("H:  %d%c", headingInt, 247);
  else
    _gfx->printf("H: %d%c", headingInt, 247);

  // Acelerómetro
  _gfx->setTextColor(RGB565_WHITE, RGB565_BLACK);
  _gfx->setTextSize(1);
  _gfx->setCursor(35, 155);
  _gfx->printf("ACC: X:%+.1f Y:%+.1f Z:%+.1f  ", data.accX, data.accY, data.accZ);

  // Giroscopio
  _gfx->setTextColor(RGB565_GREEN, RGB565_BLACK);
  _gfx->setCursor(35, 175);
  _gfx->printf("GYR: X:%+.1f Y:%+.1f Z:%+.1f  ", data.gyroX, data.gyroY, data.gyroZ);
}
