#ifndef DISCONNECTED_VIEW_H
#define DISCONNECTED_VIEW_H

#include "IView.h"

class DisconnectedView : public IView
{
private:
  BLEStatus _lastStatus;

  uint16_t getRingColor(BLEState state) const;
  String getStateText(BLEState state) const;

public:
  DisconnectedView() = default;

  ViewId getId() const override { return ViewId::DISCONNECTED; }

  void onEnter(Arduino_GFX *gfx) override;
  void onExit(Arduino_GFX *gfx) override;

  void renderStatus(Arduino_GFX *gfx, const BLEStatus &status) override;
};

#endif // DISCONNECTED_VIEW_H
