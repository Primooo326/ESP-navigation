#ifndef VIEW_UTILS_H
#define VIEW_UTILS_H

#include <Arduino_GFX_Library.h>

class ViewUtils
{
public:
  static void drawCenteredText(Arduino_GFX *gfx, const String &text, int cy, uint8_t textSize, uint16_t textColor, uint16_t bgColor = RGB565_BLACK)
  {
    if (!gfx || text.length() == 0)
      return;

    gfx->setTextSize(textSize);

    int16_t x1, y1;
    uint16_t w, h;
    gfx->getTextBounds(text.c_str(), 0, 0, &x1, &y1, &w, &h);

    int cx = 120 - (w / 2);
    if (cx < 5)
      cx = 5;

    gfx->fillRect(cx - 4, cy - 2, w + 8, h + 4, bgColor);
    gfx->setTextColor(textColor, bgColor);
    gfx->setCursor(cx, cy);
    gfx->print(text);
  }
};

#endif // VIEW_UTILS_H
