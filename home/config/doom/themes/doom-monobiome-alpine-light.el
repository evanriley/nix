;;; doom-monobiome-alpine-light.el --- Monobiome Alpine light -*- lexical-binding: t; no-byte-compile: t; -*-
;; Values mirrored from modules/theme/palette.nix; keep in sync.

(require 'doom-themes)

(def-doom-theme doom-monobiome-alpine-light
  "A light theme built from the Monobiome Alpine palette."

  :family 'doom-monobiome-alpine
  :background-mode 'light

  ((bg         '("#f5f5f5"))
   (fg         '("#333333"))
   (bg-alt     '("#e4e4e4"))
   (fg-alt     '("#959595"))
   (base0      '("#f5f5f5"))
   (base1      '("#e4e4e4"))
   (base2      '("#d4d4d4"))
   (base3      '("#c4c4c4"))
   (base4      '("#959595"))
   (base5      '("#5b5b5b"))
   (base6      '("#4d4d4d"))
   (base7      '("#404040"))
   (base8      '("#333333"))
   (grey       base4)
   (red        '("#db4b3d"))
   (orange     '("#a4672a"))
   (green      '("#4e8757"))
   (teal       '("#396740"))
   (yellow     '("#a4672a"))
   (blue       '("#4d7ad1"))
   (dark-blue  '("#4d7ad1"))
   (magenta    '("#b62920"))
   (violet     '("#365da9"))
   (cyan       '("#396740"))
   (dark-cyan  '("#4e8757"))
   (gold       '("#7f7a42"))

   (highlight      blue)
   (vertical-bar   base3)
   (selection      base2)
   (builtin        magenta)
   (comments       base4)
   (doc-comments   base5)
   (constants      violet)
   (functions      magenta)
   (keywords       blue)
   (methods        cyan)
   (operators      blue)
   (type           orange)
   (strings        green)
   (variables      magenta)
   (numbers        orange)
   (region         (doom-darken bg-alt 0.05))
   (error          red)
   (warning        orange)
   (success        green)
   (vc-modified    orange)
   (vc-added       green)
   (vc-deleted     red)

   (modeline-fg              fg)
   (modeline-fg-alt          base5)
   (modeline-bg              (doom-darken bg-alt 0.05))
   (modeline-bg-alt          (doom-darken bg-alt 0.1))
   (modeline-bg-inactive     bg-alt)
   (modeline-bg-inactive-alt (doom-darken bg-alt 0.05)))

  (((line-number &override) :foreground base4)
   ((line-number-current-line &override) :foreground fg)
   (mode-line
    :background modeline-bg :foreground modeline-fg)
   (mode-line-inactive
    :background modeline-bg-inactive :foreground modeline-fg-alt)
   (mode-line-emphasis :foreground highlight)
   (solaire-mode-line-face
    :inherit 'mode-line :background modeline-bg-alt)
   (solaire-mode-line-inactive-face
    :inherit 'mode-line-inactive :background modeline-bg-inactive-alt))

  ())
