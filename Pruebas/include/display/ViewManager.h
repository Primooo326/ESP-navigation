#ifndef VIEW_MANAGER_H
#define VIEW_MANAGER_H

#include <Arduino_GFX_Library.h>
#include "views/IView.h"
#include "views/DisconnectedView.h"
#include "views/ClockWeatherView.h"
#include "views/NavigationHUDView.h"
#include "views/CatalogPreviewView.h"
#include "views/CompassRoseView.h"
#include "views/TripStatsView.h"
#include "views/QuickSettingsView.h"

class ViewManager
{
private:
  Arduino_GFX *_gfx;

  // Instancias pre-asignadas estáticas (0 fragmentación Heap RAM)
  DisconnectedView _disconnectedView;
  ClockWeatherView _clockWeatherView;
  NavigationHUDView _navigationHUDView;
  CatalogPreviewView _catalogPreviewView;
  CompassRoseView _compassRoseView;
  TripStatsView _tripStatsView;
  QuickSettingsView _quickSettingsView;

  IView *_activeView;
  ViewId _currentViewId;

  BLEStatus _lastStatus;
  NavigationPacket _lastNav;
  bool _showQuickSettings;
  uint8_t _subViewIndex; // Para carrusel lateral (0 = Nav/Clock, 1 = Compass, 2 = Stats)

public:
  ViewManager();

  void setGfx(Arduino_GFX *gfx) { _gfx = gfx; }

  void init();
  void switchToView(ViewId id);

  ViewId getCurrentViewId() const { return _currentViewId; }
  IView *getActiveView() const { return _activeView; }

  // Gestos táctiles
  void handleSwipeLeft();
  void handleSwipeRight();
  void handleSwipeDown();
  void handleSwipeUp();
  void handleTap(uint16_t x, uint16_t y, uint8_t &brightnessLevel, uint8_t pinBl);

  // Despachadores estricto SOLID a la vista activa
  void dispatchStatus(const BLEStatus &status);
  void dispatchSensorData(const SensorData &data);
  void dispatchNavigationData(const NavigationPacket &navData);
};

#endif // VIEW_MANAGER_H
