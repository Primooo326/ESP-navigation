#ifndef CATALOG_PREVIEW_VIEW_H
#define CATALOG_PREVIEW_VIEW_H

#include "IView.h"
#include "../NavIcons.h"
#include "../NavIconsXBM.h"

class CatalogPreviewView : public IView
{
private:
  NavigationPacket _lastNav;
  uint8_t _lastIcon;
  char _lastStreet[16];

  void drawTurnArrow(Arduino_GFX *gfx, uint8_t turnIcon, int cx, int cy, uint16_t color);

public:
  CatalogPreviewView();

  ViewId getId() const override { return ViewId::CATALOG_PREVIEW; }

  void onEnter(Arduino_GFX *gfx) override;
  void onExit(Arduino_GFX *gfx) override;

  // Filtro estricto SOLID: Ignora datos de sensores (brújula/azimut) por completo
  void renderSensorData(Arduino_GFX *gfx, const SensorData &data) override {}

  void renderNavigationData(Arduino_GFX *gfx, const NavigationPacket &navData) override;
};

#endif // CATALOG_PREVIEW_VIEW_H
