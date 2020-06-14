:" -------------------------------------------------------------------------------------------
"  PLUGINS
" -------------------------------------------------------------------------------------------

" Call vim-plug
call plug#begin()

" -------------------------------------------------------------------------------------------
" SYNTAX & HIGHTLIGHTING
" -------------------------------------------------------------------------------------------

" HTML
Plug 'othree/html5.vim',            {'for': ['html', 'vue', 'jsx', 'eelixir', 'gtpl']} " HTML5 syntax & completion
Plug 'valloric/MatchTagAlways',     {'for': ['html', 'vue', 'jsx', 'eelixir', 'gtpl']} " Highlights matching tag

" CSS & Styling
Plug 'hail2u/vim-css3-syntax',      {'for': ['css', 'vue']} " CSS and SCSS syntax & highlighting
Plug 'cakebaker/scss-syntax.vim',   {'for': ['scss', 'vue']} " SCSS syntax
Plug 'wavded/vim-stylus',           {'for': ['stylus', 'vue']} " Stylus syntax & highlighting
Plug 'ap/vim-css-color',            {'for': ['css', 'scss', 'stylus', 'vue']} " Show colors on CSS files

" Javascript
Plug 'othree/yajs.vim',             {'for': ['javascript', 'vue', 'jsx']} " Javascript syntax
Plug 'othree/jspc.vim',             {'for': ['javascript', 'vue', 'jsx']} " Javascript parameter completion
Plug 'moll/vim-node',               {'for': ['javascript', 'vue', 'jsx']} " Node tools
Plug 'posva/vim-vue',               {'for': 'vue'}                                          " Vue.js syntax highlighting

" Json
Plug 'elzr/vim-json',               {'for': 'json'} " JSON highlighting

" Yaml
Plug 'stephpy/vim-yaml',            {'for': 'yaml'} " Yaml syntax highlighting

" Elixir
Plug 'elixir-editors/vim-elixir',   {'for': 'elixir'} " Elixir language highlighting
" Plug 'slashmili/alchemist.vim',     {'for': 'elixir'} " Elixir Integration

" Go
Plug 'fatih/vim-go',                {'do': ':GoInstallBinaries', 'for': 'go'} " Golang utilities

" Rust
Plug 'rust-lang/rust.vim',          {'for': 'rust'} " Rust lang highlighting

" Crystal
Plug 'rhysd/vim-crystal',           {'for': 'crystal'} " Crystal language highlighting

" Ruby
Plug 'vim-ruby/vim-ruby',           {'for': 'ruby'} " Ruby language syntax & highlighting
Plug 'tpope/vim-rails',             {'for': 'ruby'} " Rails syntax and helpers

" Clojure
" Plug 'tpope/vim-salve'
Plug 'eraserhd/parinfer-rust', {'do':
        \  'cargo build --release'}
Plug 'tpope/vim-fireplace'
" Plug 'Olical/conjure', { 'tag': 'v2.1.0', 'do': 'bin/compile' }

" Nim
Plug 'zah/nim.vim'

" Tools
Plug 'tmux-plugins/vim-tmux',       {'for': 'tmux'} " Tmux file highlighting
Plug 'cespare/vim-toml',            {'for': 'toml'} " Toml syntax highlighting
Plug 'chr4/nginx.vim',              {'for': 'nginx'} " Nginx syntax highlighting


" -------------------------------------------------------------------------------------------
" UTILITIES
" -------------------------------------------------------------------------------------------

" Delimiters
Plug 'jiangmiao/auto-pairs', { 'tag': 'v2.0.0' }
" Plug 'itmammoth/doorboy.vim'        " Auto close brackets, quotations, etc.
Plug 'tpope/vim-surround'           " Easily change surroundings (parenthesis, brackets, etc)
Plug 'tpope/vim-endwise'            " Add 'end' automatically for ruby, elixir and others

" Comments
Plug 'tpope/vim-commentary'         " Easily comment/uncomment words, lines or group of lines

" File manipulation
Plug 'mattn/emmet-vim',             {'for': ['html', 'vue', 'css', 'scss', 'javascript', 'jsx', 'eelixir', 'gtpl']} " Easy workflow for html & CSS

" Format/Indentation
Plug 'sbdchd/neoformat'             " Format code: standard.js, prettier etc.
Plug 'junegunn/vim-easy-align'      " Easy alignement
" Plug 'Yggdroot/indentLine'          " Show a line to display indentation level
Plug 'AndrewRadev/splitjoin.vim',   {'on': ['SplitjoinJoin', 'SplitjoinSplit']} " Transition between multiline and single-line code

" Editing S-expresions
" Plug 'guns/vim-sexp'
" Plug 'tpope/vim-sexp-mappings-for-regular-people'
" Plug 'vim-scripts/paredit.vim'
" Plug 'luochen1990/rainbow'

" Git
" Plug 'lambdalisue/gina.vim'         " Control GIT repos from nvim session
Plug 'airblade/vim-gitgutter'       " Show GIT changes status in the gutter
Plug 'jreybert/vimagit',            {'on': 'Magit'} " Easier GIT workflow
Plug 'tpope/vim-fugitive'          " mainly for showing Git status in netrw

" Nerdtree
" Plug 'scrooloose/nerdtree'          " Directory & files tree
" Plug 'Xuyuanp/nerdtree-git-plugin'  " Nerdtree plugin to show GIT flags

"vim-vinegar
Plug 'tpope/vim-vinegar'              " makes netrw better

" Skim fuzzy finder
" Plug 'lotabout/skim',               {'dir': '~/.skim', 'do': './install --bin', 'on': ['SK']} " FZF option in Rust lang

"fzf fuzzy finder
Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' }
Plug 'junegunn/fzf.vim'

" popup window with fuzzy finding
Plug 'liuchengxu/vim-clap'

" Denite
Plug 'Shougo/denite.nvim'           " Multiple helpful functions: open files, search, change folder, etc.
Plug 'Shougo/neomru.vim'            " Most recent used files source for denite/unite

" Testing
Plug 'janko-m/vim-test'             " Run tests from inside Neovim

" better everything about text objects
Plug 'wellle/targets.vim'

" Incremental search
Plug 'haya14busa/incsearch.vim'

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

" -------------------------------------------------------------------------------------------
" COMPLETION
" -------------------------------------------------------------------------------------------

" Deoplete
Plug 'Shougo/deoplete.nvim',        { 'do': ':UpdateRemotePlugins' } " Completion
Plug 'Shougo/context_filetype.vim'  " Find nested filetypes for example javascript on html files
Plug 'Shougo/neoinclude.vim'        " Include completion framework
Plug 'Shougo/neco-syntax'           " Syntax source

" Floating code compleition window.
Plug 'ncm2/float-preview.nvim'

" Language Server Protocol (LSP)
Plug 'autozimu/LanguageClient-neovim', { 'branch': 'next', 'do': 'bash install.sh' }

" Snippets
Plug 'Shougo/neosnippet.vim'        " Snippets support
Plug 'Shougo/neosnippet-snippets'   " Snippets repository
Plug 'Shougo/echodoc.vim'           " Show functions signatures in the command line

" Deoplete filetype sources
Plug 'carlitux/deoplete-ternjs',      {'for': ['javascript', 'vue', 'jsx']} " Javascript completion
Plug 'zchee/deoplete-go',             {'do': 'make', 'for': 'go'} " Golang completion
Plug 'racer-rust/vim-racer',          {'for': 'rust'} " Rust completion
Plug 'fishbullet/deoplete-ruby',      {'for': 'ruby'} " Ruby completion
Plug 'Shougo/neco-vim',               {'for': 'vim'}  " Vim script completion
Plug 'ponko2/deoplete-fish',          {'for': 'fish'} " Fish shell completion

" Other sources
Plug 'wellle/tmux-complete.vim'       " Adjacent tmux panes completion

" -------------------------------------------------------------------------------------------
" LINTERS
" -------------------------------------------------------------------------------------------

" Main lintting framework
Plug 'w0rp/ale'

" -------------------------------------------------------------------------------------------
" THEMES & UI
" -------------------------------------------------------------------------------------------

Plug 'arcticicestudio/nord-vim', { 'as': 'nord' }     " Nord Vim theme
Plug 'mhartington/oceanic-next'     " Oceanic Next theme
Plug 'trevordmiller/nova-vim'       " Nova theme
Plug 'junegunn/seoul256.vim'        " Seoul256 Theme
Plug 'sonph/onehalf'

" Status line
" Plug 'vim-airline/vim-airline'      " Airline plugin
Plug 'itchyny/lightline.vim'

call plug#end()
