#include "display/ViewManager.h"

ViewManager::ViewManager()
    : _gfx(nullptr), _activeView(&_disconnectedView), _currentViewId(ViewId::DISCONNECTED),
      _showQuickSettings(false), _subViewIndex(0)
{
}

void ViewManager::init()
{
  switchToView(ViewId::DISCONNECTED);
}

void ViewManager::switchToView(ViewId id)
{
  if (_currentViewId == id && _activeView != nullptr)
    return;

  if (_activeView && _gfx)
  {
    _activeView->onExit(_gfx);
  }

  _currentViewId = id;

  switch (id)
  {
  case ViewId::DISCONNECTED:
    _activeView = &_disconnectedView;
    break;
  case ViewId::CLOCK_WEATHER:
    _activeView = &_clockWeatherView;
    break;
  case ViewId::NAVIGATION_HUD:
    _activeView = &_navigationHUDView;
    break;
  case ViewId::CATALOG_PREVIEW:
    _activeView = &_catalogPreviewView;
    break;
  case ViewId::COMPASS_ROSE:
    _activeView = &_compassRoseView;
    break;
  case ViewId::TRIP_STATS:
    _activeView = &_tripStatsView;
    break;
  case ViewId::QUICK_SETTINGS:
    _activeView = &_quickSettingsView;
    break;
  default:
    _activeView = &_clockWeatherView;
    break;
  }

  if (_activeView && _gfx)
  {
    _activeView->onEnter(_gfx);
  }
}

void ViewManager::dispatchStatus(const BLEStatus &status)
{
  _lastStatus = status;

  if (status.state != BLEState::CONNECTED)
  {
    switchToView(ViewId::DISCONNECTED);
  }

  if (_activeView && _gfx)
  {
    _activeView->renderStatus(_gfx, status);
  }
}

void ViewManager::dispatchSensorData(const SensorData &data)
{
  // Despacho SOLID: Únicamente a la vista activa
  if (_activeView && _gfx)
  {
    _activeView->renderSensorData(_gfx, data);
  }
}

void ViewManager::dispatchNavigationData(const NavigationPacket &navData)
{
  _lastNav = navData;

  if (_lastStatus.state == BLEState::CONNECTED && !_showQuickSettings)
  {
    if (navData.navState == 3)
    {
      switchToView(ViewId::CATALOG_PREVIEW);
    }
    else if (navData.navState == 1 || navData.navState == 2)
    {
      if (_subViewIndex == 0)
        switchToView(ViewId::NAVIGATION_HUD);
      else if (_subViewIndex == 1)
        switchToView(ViewId::COMPASS_ROSE);
      else if (_subViewIndex == 2)
        switchToView(ViewId::TRIP_STATS);
    }
    else // navState == 0 (Sin navegación activa)
    {
      if (_subViewIndex == 0)
        switchToView(ViewId::CLOCK_WEATHER);
      else if (_subViewIndex == 1)
        switchToView(ViewId::COMPASS_ROSE);
      else if (_subViewIndex == 2)
        switchToView(ViewId::TRIP_STATS);
    }
  }

  // Despacho estricto a la vista activa
  if (_activeView && _gfx)
  {
    _activeView->renderNavigationData(_gfx, navData);
  }
}

void ViewManager::handleSwipeLeft()
{
  if (_showQuickSettings) return;
  _subViewIndex = (_subViewIndex + 1) % 3;

  if (_subViewIndex == 0)
  {
    if (_lastNav.navState == 1 || _lastNav.navState == 2)
      switchToView(ViewId::NAVIGATION_HUD);
    else if (_lastNav.navState == 3)
      switchToView(ViewId::CATALOG_PREVIEW);
    else
      switchToView(ViewId::CLOCK_WEATHER);
  }
  else if (_subViewIndex == 1)
  {
    switchToView(ViewId::COMPASS_ROSE);
  }
  else if (_subViewIndex == 2)
  {
    switchToView(ViewId::TRIP_STATS);
  }
}

void ViewManager::handleSwipeRight()
{
  if (_showQuickSettings) return;
  _subViewIndex = (_subViewIndex + 2) % 3;

  if (_subViewIndex == 0)
  {
    if (_lastNav.navState == 1 || _lastNav.navState == 2)
      switchToView(ViewId::NAVIGATION_HUD);
    else if (_lastNav.navState == 3)
      switchToView(ViewId::CATALOG_PREVIEW);
    else
      switchToView(ViewId::CLOCK_WEATHER);
  }
  else if (_subViewIndex == 1)
  {
    switchToView(ViewId::COMPASS_ROSE);
  }
  else if (_subViewIndex == 2)
  {
    switchToView(ViewId::TRIP_STATS);
  }
}

void ViewManager::handleSwipeDown()
{
  _showQuickSettings = true;
  switchToView(ViewId::QUICK_SETTINGS);
}

void ViewManager::handleSwipeUp()
{
  if (_showQuickSettings)
  {
    _showQuickSettings = false;
    if (_subViewIndex == 0)
    {
      if (_lastNav.navState == 1 || _lastNav.navState == 2)
        switchToView(ViewId::NAVIGATION_HUD);
      else if (_lastNav.navState == 3)
        switchToView(ViewId::CATALOG_PREVIEW);
      else
        switchToView(ViewId::CLOCK_WEATHER);
    }
    else if (_subViewIndex == 1)
      switchToView(ViewId::COMPASS_ROSE);
    else if (_subViewIndex == 2)
      switchToView(ViewId::TRIP_STATS);
  }
}

void ViewManager::handleTap(uint16_t x, uint16_t y, uint8_t &brightnessLevel, uint8_t pinBl)
{
  if (_showQuickSettings)
  {
    if (y < 65)
    {
      handleSwipeUp();
    }
    else if (x < 100 && y >= 65 && y <= 150)
    {
      brightnessLevel = (brightnessLevel >= 55) ? brightnessLevel - 25 : 30;
      analogWrite(pinBl, brightnessLevel);
      _quickSettingsView.setBrightness(brightnessLevel);
      if (_gfx) _quickSettingsView.update(_gfx);
    }
    else if (x > 140 && y >= 65 && y <= 150)
    {
      brightnessLevel = (brightnessLevel <= 230) ? brightnessLevel + 25 : 255;
      analogWrite(pinBl, brightnessLevel);
      _quickSettingsView.setBrightness(brightnessLevel);
      if (_gfx) _quickSettingsView.update(_gfx);
    }
  }
}
