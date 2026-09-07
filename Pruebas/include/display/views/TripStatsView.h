#ifndef TRIP_STATS_VIEW_H
#define TRIP_STATS_VIEW_H

#include "IView.h"

class TripStatsView : public IView
{
private:
  NavigationPacket _lastNav;

public:
  TripStatsView() = default;

  ViewId getId() const override { return ViewId::TRIP_STATS; }

  void onEnter(Arduino_GFX *gfx) override;
  void onExit(Arduino_GFX *gfx) override;

  void renderNavigationData(Arduino_GFX *gfx, const NavigationPacket &navData) override;
};

#endif // TRIP_STATS_VIEW_H
