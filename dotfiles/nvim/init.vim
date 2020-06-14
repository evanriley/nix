
"------------------------------------------------------------------------------"
"                                   Settings                                   "
"------------------------------------------------------------------------------"

scriptencoding utf-8
set encoding=utf-8

" Use full Vim features
set nocompatible

" Python 3 is needed for some plugins to work
let g:python3_host_prog = '/usr/local/bin/python3'

set termguicolors
" I like block & always blinking cursor
set guicursor=a:block-blinkwait100-blinkoff150-blinkon175

" Remap leader (Use space as leader)
let g:mapleader = ' '
" Map local leader
let g:maplocalleader = ','

" Release keymappings prefixes, evict entirely for use of plug-ins.
nnoremap <Space> <Nop>
xnoremap <Space> <Nop>
nnoremap ,       <Nop>
xnoremap ,       <Nop>
nnoremap ;       <Nop>
xnoremap ;       <Nop>

" Global Settings
filetype plugin indent on                       " Enable full filetype detection
syntax on                                       " Syntax highlighting on
syntax enable                                   " Syntax highlighting on
set nopaste
set title                                       " Let Vim set window title
set hidden                                      " Enable buffers on background without saving
set autochdir                                   " Change dir to file on current window
set synmaxcol=240                               " Don't syntax highlight long lines
set omnifunc=syntaxcomplete#Complete


" Positioning
set number                                      " Set line number
set ruler                                       " Set line/col of cursor

" UI
set noshowmode                                  " Dont display current mode (Using vim-airline for that)
set scrolloff=999                               " Cursor always on center of screen
set sidescrolloff=5                             " Keep at least 5 lines left/right
set shortmess=aoOtTI                            " Short messages
set showcmd                                     " Shows current command combo
set showmatch                                   " Show matching brackets
set mat=2                                       " How many tenths of a second to blink matching brackets
set mouse=n                                     " Use basic mouse for changing windows split sizes
set clipboard+=unnamedplus                      " Yank and paste with the system clipboard
set pumheight=10                                " Completion window max height
set numberwidth=2                               " Keep line number gutter cozy
set list                                        " Show hidden characters
set listchars=tab:▸\ ,trail:·,nbsp:␣            " Display tabs and trailing spaces
set listchars+=extends:»                        " show a » when a line goes off the right edge of the screen
set listchars+=precedes:«                       " show a « when a line goes off the left edge of the screenk
set conceallevel=2
set colorcolumn=81                              " Color the colum 81

" Files
set autowrite                                   " Autosave before :next, :make, etc.
set autoread                                    " Autoread file when changed outside of Vim
set noswapfile                                  " No swapfile for buffer
set nobackup                                    " Don't create annoying backup files
set confirm                                     " Ask for confirmation if unsaved file

" Completion
set wildmenu                                    " Menu for command line completion using <TAB>
set wildmode=list:longest,list:full
set wildignorecase                              " Ignore case
set wildignore+=*.zip,*.tar,*.tar*,*.rar        " Ignore archive files
set wildignore+=*.png,*.jpg,*.jpeg,*.gif        " Ignore images
set wildignore+=*.pdf                           " Ignore several files and directories
set wildignore+=*.DS_Store
set wildignore+=*yarn.lock*
set wildignore+=*.gem,*.obj,*.out,*.swp
set wildignore+=.git,.hg,*/.git/*,**/.git/**
set wildignore+=*/.bundle/*
set wildignore+=*/.sass-cache/*
set wildignore+=*/node_modules/*,**/node_modules/**
set wildignore+=**/vendor/**
set wildignore+=**/build/**
set wildignore+=**/deps/**
set wildignore+=**/log/**
set wildignore+=*/tmp/*,**/tmp/**


" Tabs/Spaces
set autoindent                                  " Auto indent
set smartindent                                 " Smart autoindenting on new lines
set expandtab                                   " Always use spaces
set tabstop=2                                   " Tab size (Columns per tab)
set shiftwidth=2                                " Amount to shift by
set softtabstop=2                               " Delete x spaces on backsp.
set smarttab                                    " use 'shiftwidth' when inserting
set backspace=indent,eol,start                  " Intuitive backspacing in insert mode
set whichwrap+=<,>,h,l

" Format
set textwidth=80                                " Wrap text starting here
set nowrap                                      " Disable softwrap
set breakindent                                 " Breack with an indentation
set breakat=\ \	;:,!?                           " Long lines break chars
set linebreak                                   " Break long lines at 'breakat'
set showbreak=+                                 " Show a '+' at the beggining of wrapped lines
set splitbelow                                  " Open horizontal splits below
set splitright                                  " Open vertical splits right

" Search
set hlsearch                                    " Highligh search
set incsearch                                   " Search as you type
set infercase                                   " Ignore case in matching
set smartcase                                   " Match capitals in search
set ignorecase


" Other
set completeopt+=noselect                       " Don't select a match in menu
set visualbell                                  " Don't beep
set noerrorbells                                " Don't beep
set iskeyword+=-,_                              " Consider - and _ part of a word
set history=200                                 " Remember more commands and search history
set undolevels=100                              " Maximum levels of changes that can be undone



"------------------------------------------------------------------------------"
"                                 Autocommands                                 "
"------------------------------------------------------------------------------"

" Main autocomands
augroup main_autocmds
  autocmd!
  autocmd CompleteDone * pclose
  autocmd VimResized * wincmd =
augroup END

" Use a tab spacing of four spaces for these file types
augroup filetype_tabs
  autocmd!
  autocmd FileType go setlocal shiftwidth=4 softtabstop=4 tabstop=4
augroup END

" Autodetect some filetypes
augroup filetype_detect
  autocmd!
  autocmd BufNewFile,BufRead .tmux.conf*,tmux.conf* setf tmux
  autocmd BufNewFile,BufRead .nginx.conf*,nginx.conf*,*/nginx/* setf nginx
  autocmd BufNewFile,BufRead Procfile,config.ru,Rakefile,Gemfile,rdoc setf ruby
  autocmd BufNewFile,BufRead *.es6,*.jsx setf javascript
  autocmd BufNewFile,BufRead .tern-project setf json
  autocmd BufNewFile,BufRead *.md,*markdown setf markdown
  autocmd BufNewFile,BufRead *.yml setf yaml
  autocmd BufNewFile,BufRead *.eex setf eelixir
  autocmd BufNewFile,BufRead *.vue setf vue
  autocmd BufNewFile,BufRead *.toml setf toml
  autocmd BufNewFile,BufRead *.styl setf stylus
  autocmd BufRead,BufNewFile .babelrc setf json
  autocmd BufRead,BufNewFile .eslintrc setf json
  autocmd BufRead,BufNewFile *.gtpl setf gtpl

  autocmd FileType vue syntax sync fromstart
augroup END

" Wrap lines on these file types
augroup filetype_wrap
  autocmd!
  autocmd FileType markdown,html,text setlocal wrap linebreak
augroup END

" Mark these files as CSS style files.
augroup CSS_syntax
  autocmd!
  autocmd FileType css,scss,sass,stylus,styl setlocal iskeyword+=-
augroup END




"------------------------------------------------------------------------------"
"                                    Plugins                                   "
"------------------------------------------------------------------------------"

" Map vim-plug most used functions
nnoremap <localleader>pu :PlugUpdate<cr>
nnoremap <localleader>pc :PlugClean<cr>
nnoremap <localleader>pi :PlugInstall<cr>


call plug#begin('~/.vim/plugged')


" General
Plug 'sheerun/vim-polyglot'			" Collection of language packs for Vim

" HTML
Plug 'valloric/MatchTagAlways'			" Highlights matching HTML tags.

" Javascript
Plug 'moll/vim-node'				" Node tools

" Clojure
Plug 'eraserhd/parinfer-rust', {'do':
        \  'cargo build --release'}		" Makes using lisp easier
" Plug 'tpope/vim-fireplace', {'for': 'clojure'}
Plug 'liquidz/vim-iced', {'for': 'clojure'}


" Tools to fix my crap code
Plug 'neoclide/coc.nvim', {'branch': 'release'}
Plug 'dense-analysis/ale'


" Delimiters
Plug 'tpope/vim-surround'          		" Easily change surroundings (parenthesis, brackets, etc)

" Comments
Plug 'tpope/vim-commentary'         		" Easily comment/uncomment words, lines or group of lines


" File manip
Plug 'mattn/emmet-vim'				          " Easy workflow for html & CSS

" Format/Indentation
Plug 'sbdchd/neoformat'             		" Format code: standard.js, prettier etc.
Plug 'junegunn/vim-easy-align'      		" Easy alignement

" Git
Plug 'airblade/vim-gitgutter'       		" Show GIT changes status in the gutter
Plug 'jreybert/vimagit', {'on': 'Magit'} 	" Easier GIT workflow
Plug 'tpope/vim-fugitive'          		" mainly for showing Git status in netrw

" NETRW
Plug 'tpope/vim-vinegar'              		" makes netrw better

" File Finder
Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' }
Plug 'junegunn/fzf.vim'

" Testing
Plug 'janko-m/vim-test'             " Run tests from inside Neovim

" better everything about text objects
Plug 'wellle/targets.vim'

" Incremental search
Plug 'haya14busa/incsearch.vim'

" Snippets
Plug 'Shougo/neosnippet.vim'        " Snippets support
Plug 'Shougo/neosnippet-snippets'   " Snippets repository
Plug 'Shougo/echodoc.vim'   

" Other tools
Plug 'bogado/file-line'                 " Open a file on arbitrary line: filename:line
Plug 'AndrewRadev/switch.vim'           " Quickly switch between patterns
Plug 'christoomey/vim-tmux-navigator'   " Navigate between Tmux and Vim splits
Plug 'mtth/scratch.vim'                 " Create scratch buffer for quick notes and todo lists
Plug 'terryma/vim-multiple-cursors'     " Multiple cursors like Sublime Text's
Plug 'justinmk/vim-sneak'               " Jump to location specifies by 2 character
Plug 'hauleth/sad.vim'                  " Quick change and replace!
Plug 'matze/vim-move'                   " Easily move blocks of code, no cuting and pasting!!!
Plug 'EinfachToll/DidYouMean'           " Ask for confirmation to open file if similar names exist
Plug 'airblade/vim-rooter'              " Chage working directory to project root
Plug 'tpope/vim-eunuch'                 " UNIX file shell command helpers
Plug 'rizzatti/dash.vim',           {'on': ['Dash', 'DashKeywords', '<Plug>DashSearch']} " Easy documentation with Dash.app (OSX)
Plug 'easymotion/vim-easymotion'        " Easily move aroudn your buffer
Plug 'jiangmiao/auto-pairs'             " Auto-close brackets
Plug 'voldikss/vim-floaterm'            " Floating terminal window


" Themes & UI
Plug 'arcticicestudio/nord-vim', { 'as': 'nord' }     " Nord Vim theme
Plug 'mhartington/oceanic-next'     " Oceanic Next theme
Plug 'trevordmiller/nova-vim'       " Nova theme
Plug 'junegunn/seoul256.vim'        " Seoul256 Theme
Plug 'sonph/onehalf'
Plug 'challenger-deep-theme/vim', { 'as': 'challenger-deep' } " Challenger Deep Theme
Plug 'ayu-theme/ayu-vim'


" Status line
Plug 'itchyny/lightline.vim'

call plug#end()

" elzr/vim-json
" ==================================
let g:vim_json_syntax_conceal = 0

" posva/vim-vue
" ==================================
let g:vue_disable_pre_processors = 1

" mattn/emmet-vim
" ==================================
let g:user_emmet_mode='a'
let g:user_emmet_install_global = 0
autocmd FileType html,css,scss,vue,jsx,javascript,javascript.jsx,gtpl
            \ EmmetInstall
            \ | imap <buffer> <C-Return> <Plug>(emmet-expand-abbr)

" junegunn/vim-easy-align
" ==================================
xmap ga <Plug>(EasyAlign)
nmap ga <Plug>(EasyAlign)

" airblade/vim-gitgutter
" ==================================
let g:gitgutter_map_keys = 0
nmap <leader>g <Plug>GitGutterNextHunk
nmap <leader>G <Plug>GitGutterPrevHunk

" jreybert/vimagit
" ==================================
nnoremap <leader>gs :Magit<CR>
nnoremap <leader>gP :! git push<CR>

" tpope/vim-fugitive
" ==================================
nnoremap <Leader>gb :Gblame<CR>  " git blame

" netrw 
" ==================================
map <leader>n :Explore<cr>
map <leader>sn :Sexplore<cr>
map <leader>vn :Vexplore<cr>
let g:netrw_banner = 0
let g:netrw_liststyle = 3
let g:netrw_browse_split = 0
let g:netrw_altv = 1
let g:netrw_winsize = 10

" rizzatti/dash.vim
" ==================================
nmap <silent> <C-d> <Plug>DashSearch

" float-preview
" =================================
let g:float_preview#docked = 0
let g:float_preview#max_width = 80
let g:float_preview#max_height = 40

" zah/nim.vim
" ===================================
fun! JumpToDef()
  if exists("*GotoDefinition_" . &filetype)
    call GotoDefinition_{&filetype}()
  else
    exe "norm! \<C-]"
  endif
endfun
" Jump to tag
nn <M-g> :call JumpToDef()<cr>
ino <M-g> <esc>:call JumpToDef()<cr>i


" w0rp/ale
" ===================================
let g:ale_linters = {
      \ 'clojure': ['clj-kondo', 'joker']
      \}

" hauleth/sad.vim
" ==================================
nmap <leader>c <Plug>(sad-change-forward)
vmap <leader>c <Plug>(sad-change-forward)
nmap <leader>C <Plug>(sad-change-backward)
vmap <leader>C <Plug>(sad-change-backward)

" FZF/Ripgrep Stuff 
" ===================================
" --column: Show column number
" --line-number: Show line number
" --no-heading: Do not show file headings in results
" --fixed-strings: Search term as a literal string
" --ignore-case: Case insensitive search
" --no-ignore: Do not respect .gitignore, etc...
" --hidden: Search hidden files and folders
" --follow: Follow symlinks
" --glob: Additional conditions for search (in this case ignore everything in the .git/ folder)
" --color: Search color options
command! -bang -nargs=* Find call fzf#vim#grep('rg --column --line-number --no-heading --fixed-strings --ignore-case --no-ignore --hidden --follow --glob "!.git/*" --color "always" '.shellescape(<q-args>), 1, <bang>0)
nnoremap <C-p> :FZF<CR> 




"------------------------------------------------------------------------------"
"                                   Functions                                  "
"------------------------------------------------------------------------------"


" Strip trailing whitespace
function! StripWhitespace ()
    let save_cursor = getpos(".")
    let old_query = getreg('/')
    :%s/\s\+$//e
    call setpos('.', save_cursor)
    call setreg('/', old_query)
endfunction
noremap <leader>ss :call StripWhitespace()<CR>


" Add semicolon to at the end of a line
function! AddSemicolon()
    execute "normal! mqA;\<esc>`q"
endfunction

nmap <leader>as :call AddSemicolon()<cr>

" Select all file to clipboard
function! CopyAll()
    execute "normal! %y<cr>"
endfunction

nmap <leader>y :call CopyAll()<cr>



"------------------------------------------------------------------------------"
"                                   Keybinds                                   "
"------------------------------------------------------------------------------"

" Navigation
noremap H ^
noremap L g_
noremap J 5j
noremap K 5k

" Make cursor move by visual lines instead of file lines (when wrapping) unless count is prepended
noremap <expr> j v:count ? 'j' : 'gj'
noremap <expr> k v:count ? 'k' : 'gk'

" Go to definition (using ctags)
nnoremap <leader>z <C-]>

" Buffer Navigation
nnoremap <leader>. :bn!<cr>
nnoremap <leader>, :bp!<cr>
nnoremap <leader>d :bd<cr>
nnoremap <leader>- :enew<cr>

" upper/lower word
nnoremap <leader>u mQviwU`Q
nnoremap <leader>l mQviwu`Q

" upper/lower first char of word
nnoremap <leader>U mQgewvU`Q
nnoremap <leader>L mQgewvu`Q

" Easy save & quit
nnoremap <leader>w :w<cr>
nnoremap <leader>q :q<cr>
nnoremap <leader>x :wq<cr>

" Make :Q and :W work like :q and :w
command! W :w
command! Q :q
command! Qa :qa

" Start an external command with a single bang
nnoremap ! :!

" Make Y consistent with C and D
nnoremap Y y$

" Don't add single character removal to the default registry
noremap x "_x
vmap x "_d

" Remove line/selection without adding it to the default registry
nmap X "_dd
vmap X "_d

" When changing text, don't add it to default registry
nnoremap c "_c
vnoremap c "_c
nnoremap C "_C
vnoremap C "_C

" Insert blank line up/down cursor position in normal mode
nnoremap <leader><cr> o<esc>
nnoremap <leader><bs> O<esc>

" NO ARROW KEYS COME ON!!!
noremap <Left>  :echo "no! use h"<cr>
noremap <Right> :echo "no! use l"<cr>
noremap <Up>    :echo "no! use k"<cr>
noremap <Down>  :echo "no! use j"<cr>
imap <Left> <nop>
imap <Right> <nop>
imap <Up> <nop>
imap <Down> <nop>

" Navigation in command line
cnoremap <C-j> <Left>
cnoremap <C-k> <Right>
cnoremap <C-h> <Home>
cnoremap <C-l> <End>

" Change the Current working dir to where the current file is located
nnoremap <silent> <Leader>cd :cd %:p:h<CR>:pwd<CR>

" No Ex mode
nnoremap Q <nop>

" Make 'dot' work as expected in visual mode
vnoremap . :norm.<cr>
xnoremap . :norm.<cr>

" Clear the search buffer when hitting ESC
map <silent> <esc> :nohlsearch<cr>

" Select pasted text to work with it or select all if not pasted text
nnoremap <leader>v `[v`]

" Keep block selected after indenting
xnoremap > >gv|
xnoremap < <gv

" Use <Tab> for indenting in visual mode
vnoremap <Tab> >gv|
vnoremap <S-Tab> <gv

" Use '<' and '>' for indenting in normal mode
nnoremap > >>_
nnoremap < <<_

" easy switch
nnoremap <tab> %

" ESC from insert mode
imap jk <Esc>
imap kj <Esc>

" Join lines and restore cursor location
nnoremap <Leader>j mjJ`j

" Switch between the last two files
noremap <leader>m <c-^>

" Reload & easy edit Neovim configuration
" nnoremap <leader>r :source ~/.config/nvim/init.vim<cr>
" nnoremap <leader>e :e ~/.config/nvim/init.vim<cr>

" Enter normal mode in terminal buffer and change buffers
tnoremap <Esc> <C-\><C-n>
tnoremap <leader>. <c-\><c-n>:bn<cr>
tnoremap <leader>, <c-\><c-n>:bp<cr>

" Easy exit terminal buffer
tmap <leader>d <c-\><c-n>:bd!<cr>

" Cope, super helpful, do ':help cope' if unsure
nnoremap <localleader>cc :botright cope<cr>
nnoremap <localleader>n :cn<cr>
nnoremap <localleader>p :cp<cr>


" Mapping incsearch bindings
map /  <Plug>(incsearch-forward)
map ?  <Plug>(incsearch-backward)
map g/ <Plug>(incsearch-stay)

" Various settings to make using Coc.vim better/
set cmdheight=2
set updatetime=300
set shortmess+=c
set signcolumn=yes

" Use tab for trigger completion with characters ahead and navigate.
" NOTE: Use command ':verbose imap <tab>' to make sure tab is not mapped by
" other plugin before putting this into your config.
inoremap <silent><expr> <TAB>
      \ pumvisible() ? "\<C-n>" :
      \ <SID>check_back_space() ? "\<TAB>" :
      \ coc#refresh()
inoremap <expr><S-TAB> pumvisible() ? "\<C-p>" : "\<C-h>"

function! s:check_back_space() abort
  let col = col('.') - 1
  return !col || getline('.')[col - 1]  =~# '\s'
endfunction

" Use `[g` and `]g` to navigate diagnostics
nmap <silent> [g <Plug>(coc-diagnostic-prev)
nmap <silent> ]g <Plug>(coc-diagnostic-next)

" GoTo code navigation.
nmap <silent> gd <Plug>(coc-definition)
nmap <silent> gy <Plug>(coc-type-definition)
nmap <silent> gi <Plug>(coc-implementation)
nmap <silent> gr <Plug>(coc-references)

" Use K to show documentation in preview window.
nnoremap <silent> K :call <SID>show_documentation()<CR>


function! s:show_documentation()
  if (index(['vim','help'], &filetype) >= 0)
    execute 'h '.expand('<cword>')
  else
    call CocAction('doHover')
  endif
endfunction


" Highlight the symbol and its references when holding the cursor.
autocmd CursorHold * silent call CocActionAsync('highlight')


" Symbol renaming.
nmap <leader>rn <Plug>(coc-rename)

" Formatting selected code.
xmap <leader>f  <Plug>(coc-format-selected)
nmap <leader>f  <Plug>(coc-format-selected)

" Use <TAB> for selections ranges.
" NOTE: Requires 'textDocument/selectionRange' support from the language server.
" coc-tsserver, coc-python are the examples of servers that support it.
nmap <silent> <TAB> <Plug>(coc-range-select)
xmap <silent> <TAB> <Plug>(coc-range-select)


" Add `:Format` command to format current buffer.
command! -nargs=0 Format :call CocAction('format')

" Add `:Fold` command to fold current buffer.
command! -nargs=? Fold :call     CocAction('fold', <f-args>)

" Add `:OR` command for organize imports of the current buffer.
command! -nargs=0 OR   :call     CocAction('runCommand', 'editor.action.organizeImport')

" Add :Prettier to format code 
command! -nargs=0 Prettier :CocCommand prettier.formatFile


" ALE linter settings
let g:ale_linters = {
      \ 'javascript': ['eslint'],
      \ 'clojure': ['clj-kondo'],
      \ 'rust': ['rls'],
      \}

" Coc settings
let g:coc_global_extensions = ['coc-tsserver', 'coc-rls', 'coc-eslint', 
                            \  'coc-prettier', 'coc-json', 'coc-css',
                            \  'coc-marketplace',]


" Vim-Iced settings
let g:iced_enable_default_key_mappings = v:true

" Vim-floaterm settings
let g:floaterm_keymap_new    = '<Leader>t'
let g:floaterm_keymap_prev   = '<Leader><'
let g:floaterm_keymap_next   = '<Leader>>'
let g:floaterm_keymap_toggle = '<Leader>T'




"------------------------------------------------------------------------------"
"                             Themes / Colors / UI                             "
"------------------------------------------------------------------------------"

" let g:seoul256_background = 233
" colo seoul256

let ayucolor="dark" 
colorscheme ayu


if has('nvim') || has('termguicolors')
  set termguicolors
endif

let g:lightline = { 'colorscheme': 'ayu' }
