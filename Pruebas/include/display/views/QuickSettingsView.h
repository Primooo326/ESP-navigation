#ifndef QUICK_SETTINGS_VIEW_H
#define QUICK_SETTINGS_VIEW_H

#include "IView.h"

class QuickSettingsView : public IView
{
private:
  uint8_t _brightness;

public:
  QuickSettingsView();

  ViewId getId() const override { return ViewId::QUICK_SETTINGS; }

  void setBrightness(uint8_t b) { _brightness = b; }

  void onEnter(Arduino_GFX *gfx) override;
  void onExit(Arduino_GFX *gfx) override;

  void update(Arduino_GFX *gfx) override;
};

#endif // QUICK_SETTINGS_VIEW_H
