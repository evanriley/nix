;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

(setq user-full-name "Evan Riley"
      user-mail-address "evan@evanriley.com")

(setq doom-font (font-spec :family "Berkeley Mono" :size 14)
      doom-variable-pitch-font (font-spec :family "Noto Sans" :size 14)
      doom-serif-font (font-spec :family "Noto Serif" :size 14)
      ispell-dictionary "en")

(defun evan/desktop-mode ()
  "Return the desktop palette mode, defaulting to dark."
  (let ((file (expand-file-name "~/.config/theme/mode")))
    (if (file-readable-p file)
        (with-temp-buffer
          (insert-file-contents file)
          (if (string= (string-trim (buffer-string)) "light") 'light 'dark))
      'dark)))

(defun evan/load-monobiome-theme ()
  "Load the Monobiome Alpine theme matching `evan/desktop-mode'.
The theme files are not named with Emacs' `-theme.el' suffix, so load
them explicitly before enabling."
  (interactive)
  (let* ((mode (evan/desktop-mode))
         (theme (if (eq mode 'light)
                    'doom-monobiome-alpine-light
                  'doom-monobiome-alpine-dark))
         (file (doom-user-dir (format "themes/%s" theme))))
    (unless (custom-theme-p theme)
      (load file nil t))
    (mapc #'disable-theme custom-enabled-themes)
    (enable-theme theme)))

(evan/load-monobiome-theme)

(use-package! pilish
  :init
  (setq pilish-essential-grammar-action 'auto)
  (defalias 'pi 'pilish))

(after! pilish
  (map! :map pilish-input-mode-map
        :localleader
        :desc "send" "s" #'pilish-send
        :desc "abort" "k" #'pilish-abort
        :desc "menu" "m" #'pilish-menu
        :desc "sessions" "r" #'pilish-session-browser
        :desc "steer" "t" #'pilish-queue-steering
        :desc "compact" "c" #'pilish-compact
        :desc "attach image" "i" #'pilish-attach-image
        :desc "select model" "M" #'pilish-select-model
        :desc "cycle thinking" "T" #'pilish-cycle-thinking
        :desc "export html" "e" #'pilish-export-html
        :desc "copy last message" "y" #'pilish-copy-last-message
        :desc "new session" "N" #'pilish-new-session
        ;; Send without leaving insert state; multi-line prompts still use RET.
        :i "C-<return>" #'pilish-send)
  (map! :map pilish-chat-mode-map
        :localleader
        :desc "abort" "k" #'pilish-abort
        :desc "menu" "m" #'pilish-menu
        :desc "sessions" "r" #'pilish-session-browser
        :desc "compact" "c" #'pilish-compact
        :desc "select model" "M" #'pilish-select-model
        :desc "cycle thinking" "T" #'pilish-cycle-thinking
        :desc "export html" "e" #'pilish-export-html
        :desc "copy last message" "y" #'pilish-copy-last-message
        :desc "new session" "N" #'pilish-new-session))

(after! parinfer-rust-mode
  (setq parinfer-rust-library (or (getenv "PARINFER_RUST_LIBRARY") parinfer-rust-library)
        parinfer-rust-auto-download t))

(use-package! consult-ghostel
  :after (ghostel consult)
  :config
  (consult-ghostel-mode 1))

(after! lsp-mode
  (setq lsp-ruff-lint-enable t))

(map! :leader
      :desc "pi" "o i" #'pilish
      :desc "pi sessions" "o I" #'pilish-session-browser
      :desc "org calendar" "o c" #'=calendar
      ;; Only one machine should sync at a time; the state file rides syncthing.
      :desc "org-caldav sync" "o C" #'org-caldav-sync
      :desc "org-roam-ui" "n r u" #'org-roam-ui-open
      :desc "toggle inline blame" "g a" #'blamer-mode)

(after! mu4e
  (setq mu4e-maildir "~/.mail"
        mu4e-sent-folder "/fastmail/Sent"
        mu4e-drafts-folder "/fastmail/Drafts"
        mu4e-trash-folder "/fastmail/Trash"
        mu4e-refile-folder "/fastmail/Archive"
        mu4e-get-mail-command "mbsync -a"
        mu4e-update-interval nil
        mu4e-mu-binary (or (getenv "MU4E_MU_BINARY") (executable-find "mu"))
        sendmail-program (executable-find "msmtp")
        message-sendmail-f-is-evil t
        message-sendmail-extra-arguments '("--read-envelope-from")
        message-send-mail-function #'message-send-mail-with-sendmail))

(after! org
  (let ((notes (expand-file-name "~/sync/notes")))
    (setq org-directory notes
          org-agenda-files (list notes)
          org-roam-directory (expand-file-name "roam" notes))))

(after! org-roam
  (with-demoted-errors "org-roam setup: %S"
    (when (file-directory-p org-roam-directory)
      (org-roam-db-autosync-mode 1))))

(use-package! org-roam-ui
  :after org-roam
  :config
  (setq org-roam-ui-open-on-start nil))

(use-package! org-caldav
  :after org
  :config
  (setq org-caldav-url "https://caldav.fastmail.com/dav/calendars/user/evan@evanriley.com"
        org-caldav-calendar-id "3DD1602A-2EA4-11F1-9E75-8227B75D5C6B"
        org-caldav-inbox (expand-file-name "~/sync/notes/calendar/inbox.org")
        org-caldav-files (list (expand-file-name "~/sync/notes/calendar/calendar.org"))
        org-caldav-save-directory (expand-file-name "~/sync/notes/calendar/")
        org-icalendar-timezone "America/New_York"
        auth-sources (cons "/run/agenix/fastmail-authinfo" auth-sources))
  (with-demoted-errors "org-caldav setup: %S"
    (make-directory org-caldav-save-directory t)))
