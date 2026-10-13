;;; $DOOMDIR/init.el -*- lexical-binding: t; -*-

(doom! :completion
       (corfu +icons +orderless +dabbrev)
       vertico

       :ui
       dashboard
       doom
       hl-todo
       (ligatures +extra)
       modeline
       nav-flash
       ophints
       (popup +defaults)
       (smooth-scroll +interpolate)
       tabs
       (vc-gutter +pretty)
       (window-select +numbers)
       workspaces

       :editor
       (evil +everywhere)
       (format +lsp)
       fold
       parinfer
       snippets
       word-wrap

       :checkers
       (spell +aspell)
       (syntax +icons)

       :emacs
       (dired +dirvish)
       (ibuffer +icons)
       (undo +tree)

       :term
       (ghostel +everywhere)

       :tools
       debugger
       direnv
       editorconfig
       eval
       lookup
       lsp
       magit
       pdf
       tree-sitter

       :lang
       (cc +lsp)
       (clojure +lsp)
       emacs-lisp
       (go +lsp)
       (java +lsp)
       (javascript +lsp)
       (json +lsp)
       markdown
       (nix +lsp +tree-sitter)
       (org +roam +pretty +dragndrop +journal)
       (python +lsp)
       (rest +jq)
       (rust +lsp)
       (sh +lsp +fish)
       (web +lsp)
       (yaml +lsp)
       (zig +lsp)

       :email
       (mu4e +org)

       :app
       calendar

       :config
       (default +bindings +smartparens))
