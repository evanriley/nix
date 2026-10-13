;;; doom-monobiome-alpine-dark.el --- Monobiome Alpine dark -*- lexical-binding: t; no-byte-compile: t; -*-
;; Values mirrored from modules/theme/palette.nix; keep in sync.

(require 'doom-themes)

(def-doom-theme doom-monobiome-alpine-dark
  "A dark theme built from the Monobiome Alpine palette."

  :family 'doom-monobiome-alpine
  :background-mode 'dark

  ((bg         '("#262626"))
   (fg         '("#e4e4e4"))
   (bg-alt     '("#333333"))
   (fg-alt     '("#777777"))
   (base0      '("#262626"))
   (base1      '("#333333"))
   (base2      '("#404040"))
   (base3      '("#4d4d4d"))
   (base4      '("#777777"))
   (base5      '("#b4b4b4"))
   (base6      '("#c4c4c4"))
   (base7      '("#d4d4d4"))
   (base8      '("#e4e4e4"))
   (grey       base4)
   (red        '("#e15344"))
   (orange     '("#c38141"))
   (green      '("#64a46e"))
   (teal       '("#87c28f"))
   (yellow     '("#c38141"))
   (blue       '("#5e8de4"))
   (dark-blue  '("#5e8de4"))
   (magenta    '("#fa8979"))
   (violet     '("#8ab1f8"))
   (cyan       '("#87c28f"))
   (dark-cyan  '("#64a46e"))
   (gold       '("#9e9858"))

   (highlight      blue)
   (vertical-bar   base3)
   (selection      base2)
   (builtin        magenta)
   (comments       base5)
   (doc-comments   base6)
   (constants      violet)
   (functions      magenta)
   (keywords       blue)
   (methods        cyan)
   (operators      blue)
   (type           orange)
   (strings        green)
   (variables      (doom-lighten magenta 0.2))
   (numbers        orange)
   (region         (doom-lighten bg-alt 0.12))
   (error          red)
   (warning        orange)
   (success        green)
   (vc-modified    orange)
   (vc-added       green)
   (vc-deleted     red)

   (modeline-fg              fg)
   (modeline-fg-alt          base5)
   (modeline-bg              (doom-darken bg-alt 0.1))
   (modeline-bg-alt          (doom-darken bg-alt 0.2))
   (modeline-bg-inactive     bg-alt)
   (modeline-bg-inactive-alt (doom-darken bg-alt 0.1)))

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
