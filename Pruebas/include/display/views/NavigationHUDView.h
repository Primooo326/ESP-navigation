#ifndef NAVIGATION_HUD_VIEW_H
#define NAVIGATION_HUD_VIEW_H

#include "IView.h"
#include "../NavIcons.h"
#include "../NavIconsXBM.h"

class NavigationHUDView : public IView
{
private:
  NavigationPacket _lastNav;

  int _lastEdgeX;
  int _lastEdgeY;
  int _lastNX;
  int _lastNY;
  int _lastFX;
  int _lastFY;

  void drawTurnArrow(Arduino_GFX *gfx, uint8_t turnIcon, int cx, int cy, uint16_t color);

public:
  NavigationHUDView();

  ViewId getId() const override { return ViewId::NAVIGATION_HUD; }

  void onEnter(Arduino_GFX *gfx) override;
  void onExit(Arduino_GFX *gfx) override;

  void renderNavigationData(Arduino_GFX *gfx, const NavigationPacket &navData) override;
};

#endif // NAVIGATION_HUD_VIEW_H
