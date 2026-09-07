#ifndef COMPASS_ROSE_VIEW_H
#define COMPASS_ROSE_VIEW_H

#include "IView.h"

class CompassRoseView : public IView
{
private:
  NavigationPacket _lastNav;
  int _lastNeedleX;
  int _lastNeedleY;

public:
  CompassRoseView();

  ViewId getId() const override { return ViewId::COMPASS_ROSE; }

  void onEnter(Arduino_GFX *gfx) override;
  void onExit(Arduino_GFX *gfx) override;

  void renderSensorData(Arduino_GFX *gfx, const SensorData &data) override;
  void renderNavigationData(Arduino_GFX *gfx, const NavigationPacket &navData) override;
};

#endif // COMPASS_ROSE_VIEW_H
