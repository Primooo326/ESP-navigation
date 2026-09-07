#include "ble/BLEManager.h"

#define SERVICE_UUID "4fa1c201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

// Callback interno para eventos de conexión del Servidor BLE
class ManagerServerCallbacks : public BLEServerCallbacks
{
private:
  BLEManager &_manager;

public:
  ManagerServerCallbacks(BLEManager &manager) : _manager(manager) {}

  void onConnect(BLEServer *pServer) override
  {
    _manager._deviceConnected = true;
    Serial.println(">> [BLEManager] Callback: Dispositivo Android conectado!");
  }

  void onDisconnect(BLEServer *pServer) override
  {
    _manager._deviceConnected = false;
    Serial.println(">> [BLEManager] Callback: Dispositivo Android desconectado.");
  }
};

// Callback interno para recepción de escrituras desde Android
class ManagerCharacteristicCallbacks : public BLECharacteristicCallbacks
{
private:
  BLEManager &_manager;

public:
  ManagerCharacteristicCallbacks(BLEManager &manager) : _manager(manager) {}

  void onWrite(BLECharacteristic *pCharacteristic) override
  {
    std::string rxValue = pCharacteristic->getValue();
    size_t len = rxValue.length();

    if (len == sizeof(NavigationPacket) || (len > 0 && (uint8_t)rxValue[0] == 1 && len >= 10))
    {
      NavigationPacket nav;
      size_t copyLen = (len < sizeof(NavigationPacket)) ? len : sizeof(NavigationPacket);
      memcpy(&nav, rxValue.data(), copyLen);
      // Garantizar que la cadena de texto siempre esté terminada en nulo '\0'
      nav.streetName[sizeof(nav.streetName) - 1] = '\0';

      _manager._latestNavData = nav;
      _manager._hasNewNavData = true;

      Serial.printf(">> [BLE RX NAV] Icon: %d | Dist: %d m | Speed: %d km/h | Street: %s\n",
                    nav.turnIcon, nav.distanceMeters, nav.speedKmh, nav.streetName);
      return;
    }

    if (len > 0)
    {
      String payload = String(rxValue.c_str());

      SensorData data;
      data.updated = true;

      float vals[7] = {0.0f};
      int valCount = 0;
      String curToken = "";

      for (size_t i = 0; i <= payload.length(); i++)
      {
        char c = (i < payload.length()) ? payload.charAt(i) : ' ';
        if ((c >= '0' && c <= '9') || c == '.' || c == '-')
        {
          curToken += c;
        }
        else
        {
          if (curToken.length() > 0 && curToken != "-")
          {
            if (valCount < 7)
            {
              vals[valCount++] = curToken.toFloat();
            }
            curToken = "";
          }
        }
      }

      if (valCount >= 1)
        data.accX = vals[0];
      if (valCount >= 2)
        data.accY = vals[1];
      if (valCount >= 3)
        data.accZ = vals[2];
      if (valCount >= 4)
        data.gyroX = vals[3];
      if (valCount >= 5)
        data.gyroY = vals[4];
      if (valCount >= 6)
        data.gyroZ = vals[5];
      if (valCount >= 7)
        data.heading = vals[6];

      _manager._latestSensorData = data;
      _manager._hasNewSensorData = true;
    }
  }
};

BLEManager::BLEManager(const String &deviceName, IBLEStatusListener *listener)
    : _deviceName(deviceName), _listener(listener),
      _pServer(nullptr), _pService(nullptr), _pCharacteristic(nullptr),
      _pServerCallbacks(nullptr), _pCharacteristicCallbacks(nullptr),
      _deviceConnected(false), _oldDeviceConnected(false),
      _hasNewSensorData(false), _hasNewNavData(false)
{
}

BLEManager::~BLEManager()
{
  if (_pServerCallbacks) delete _pServerCallbacks;
  if (_pCharacteristicCallbacks) delete _pCharacteristicCallbacks;
}

void BLEManager::setListener(IBLEStatusListener *listener)
{
  _listener = listener;
}

void BLEManager::setStatus(BLEState state, const String &detail, int rssi)
{
  _currentStatus = BLEStatus(state, detail, rssi);
  if (_listener)
  {
    _listener->onBLEStatusChanged(_currentStatus);
  }
}

void BLEManager::init()
{
  setStatus(BLEState::INIT, "Iniciando Servidor BLE...");

  BLEDevice::init(_deviceName.c_str());

  _pServer = BLEDevice::createServer();
  _pServerCallbacks = new ManagerServerCallbacks(*this);
  _pServer->setCallbacks(_pServerCallbacks);

  _pService = _pServer->createService(SERVICE_UUID);

  _pCharacteristic = _pService->createCharacteristic(
      CHARACTERISTIC_UUID,
      BLECharacteristic::PROPERTY_READ |
          BLECharacteristic::PROPERTY_WRITE |
          BLECharacteristic::PROPERTY_WRITE_NR |
          BLECharacteristic::PROPERTY_NOTIFY |
          BLECharacteristic::PROPERTY_INDICATE);

  _pCharacteristicCallbacks = new ManagerCharacteristicCallbacks(*this);
  _pCharacteristic->setCallbacks(_pCharacteristicCallbacks);
  _pCharacteristic->addDescriptor(new BLE2902());
  _pCharacteristic->setValue("0,0,0,0,0,0,0");

  _pService->start();

  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);

  BLEDevice::startAdvertising();

  Serial.println(">> [BLEManager] Servidor BLE listo. Visible como: " + _deviceName);
  setStatus(BLEState::ADVERTISING, _deviceName);
}

void BLEManager::update()
{
  // Transición al conectar un móvil Android
  if (_deviceConnected && !_oldDeviceConnected)
  {
    _oldDeviceConnected = _deviceConnected;
    setStatus(BLEState::CONNECTED, "Movil Conectado");
  }

  // Transición al desconectar: reiniciar anuncios
  if (!_deviceConnected && _oldDeviceConnected)
  {
    _oldDeviceConnected = _deviceConnected;
    setStatus(BLEState::DISCONNECTED, "Conexion Perdida");
    delay(500);
    BLEDevice::startAdvertising();
    setStatus(BLEState::ADVERTISING, _deviceName);
    Serial.println(">> [BLEManager] Anuncios reiniciados.");
  }

  // Despachar datos de sensores recibidos desde Android al hilo principal
  if (_hasNewSensorData && _deviceConnected)
  {
    _hasNewSensorData = false;
    if (_listener)
    {
      _listener->onSensorDataReceived(_latestSensorData);
    }
  }

  // Despachar datos de navegación recibidos desde Android
  if (_hasNewNavData && _deviceConnected)
  {
    _hasNewNavData = false;
    if (_listener)
    {
      _listener->onNavigationDataReceived(_latestNavData);
    }
  }
}
