#ifndef NAV_ICONS_XBM_H
#define NAV_ICONS_XBM_H

#include <Arduino.h>

// ============================================================================
// MATRICES DE BITMAPS XBM 80x80 PÍXELES EN PROGMEM (LSB First)
// Renderizadas mediante _gfx->drawXBitmap(x, y, bitmap, 80, 80, color);
// 80x80 bits = 800 bytes por ícono. Total 17 íconos = ~13.6 KB en Flash.
// ============================================================================
#include "generated_bitmaps.h"

// ============================================================================
// SANITIZADOR UTF-8 A ASCII ESTÁNDAR
// Elimina acentos y caracteres raros para pantallas LCD/Adafruit GFX
// ============================================================================
inline String sanitizeUTF8(const String &input) {
  String out = "";
  out.reserve(input.length());
  for (size_t i = 0; i < input.length(); i++) {
    uint8_t c = (uint8_t)input[i];
    if (c == 0xC3 && i + 1 < input.length()) {
      uint8_t c2 = (uint8_t)input[i + 1];
      i++;
      switch (c2) {
        case 0x80: case 0x81: case 0x82: case 0x83: case 0x84: case 0x85: // Á...
        case 0xA0: case 0xA1: case 0xA2: case 0xA3: case 0xA4: case 0xA5: // á...
          out += 'A'; break;
        case 0x88: case 0x89: case 0x8A: case 0x8B: // É...
        case 0xA8: case 0xA9: case 0xAA: case 0xAB: // é...
          out += 'E'; break;
        case 0x8C: case 0x8D: case 0x8E: case 0x8F: // Í...
        case 0xAC: case 0xAD: case 0xAE: case 0xAF: // í...
          out += 'I'; break;
        case 0x92: case 0x93: case 0x94: case 0x95: case 0x96: // Ó...
        case 0xB2: case 0xB3: case 0xB4: case 0xB5: case 0xB6: // ó...
          out += 'O'; break;
        case 0x99: case 0x9A: case 0x9B: case 0x9C: // Ú...
        case 0xB9: case 0xBA: case 0xBB: case 0xBC: // ú...
          out += 'U'; break;
        case 0x91: case 0xB1: // Ñ, ñ
          out += 'N'; break;
        default:
          out += '?'; break;
      }
    } else if (c == 0xC2 && i + 1 < input.length()) {
      uint8_t c2 = (uint8_t)input[i + 1];
      i++;
      if (c2 == 0xA1) out += ' '; // ¡
      else if (c2 == 0xAA || c2 == 0xBA) out += 'a'; // ª, º
      else out += ' ';
    } else if (c >= 32 && c <= 126) {
      if (c >= 'a' && c <= 'z') out += (char)(c - 32); // Mayúsculas para HUD limpio
      else out += (char)c;
    } else {
      out += ' ';
    }
  }
  return out;
}

// ============================================================================
// MAPEADORES AUXILIARES: XBM BITMAPS Y TEXTO ESCRITO DE CADA MANIOBRA
// ============================================================================
inline const uint8_t* getNavIconXBM(uint8_t turnIcon) {
  switch (turnIcon) {
    case 1:  return nav_xbm_straight;
    case 2:  return nav_xbm_turn_right;
    case 3:  return nav_xbm_turn_left;
    case 4:  return nav_xbm_slight_right;
    case 5:  return nav_xbm_slight_left;
    case 6:  return nav_xbm_sharp_right;
    case 7:  return nav_xbm_sharp_left;
    case 8:  return nav_xbm_roundabout_exit1;
    case 9:  return nav_xbm_arrived;
    case 10: return nav_xbm_roundabout_exit2;
    case 11: return nav_xbm_roundabout_exit3;
    case 12: return nav_xbm_roundabout_exit4;
    case 13: return nav_xbm_uturn;
    case 14: return nav_xbm_fork_right;
    case 15: return nav_xbm_fork_left;
    case 16: return nav_xbm_on_ramp;
    case 17: return nav_xbm_off_ramp;
    default: return nav_xbm_straight;
  }
}

inline const char* getNavManeuverText(uint8_t turnIcon) {
  switch (turnIcon) {
    case 1:  return "RECTO";
    case 2:  return "GIRO DERECHA";
    case 3:  return "GIRO IZQUIERDA";
    case 4:  return "LEVE DERECHA";
    case 5:  return "LEVE IZQUIERDA";
    case 6:  return "CERRADO DERECHA";
    case 7:  return "CERRADO IZQUIERDA";
    case 8:  return "ROTONDA (SALIDA 1)";
    case 9:  return "LLEGASTE A TU DESTINO";
    case 10: return "ROTONDA (SALIDA 2)";
    case 11: return "ROTONDA (SALIDA 3)";
    case 12: return "ROTONDA (SALIDA 4)";
    case 13: return "RETORNO (U-TURN)";
    case 14: return "BIFURCACION DERECHA";
    case 15: return "BIFURCACION IZQUIERDA";
    case 16: return "INCORPORACION";
    case 17: return "SALIDA AUTOPISTA";
    default: return "SMART HUD";
  }
}

#endif // NAV_ICONS_XBM_H
