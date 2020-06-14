

scriptencoding utf-8
set encoding=utf-8

" Use full Vim features
set nocompatible

" Config file path
let g:config_path = "~/.config/nvim/"


" Function for sourcing config modules
function! ConfigInc(module)
    execute 'source ' . fnameescape(g:config_path) . fnameescape(a:module)
endfunction

" Python 3 is needed for some plugins to work
let g:python3_host_prog = '/usr/local/bin/python3'

set termguicolors
" I like block & always blinking cursor
set guicursor=a:block-blinkwait100-blinkoff150-blinkon175

" -------------------------------------------------------------------------------------------
"  SETTINGS
" -------------------------------------------------------------------------------------------

call ConfigInc('settings.vim')

" -------------------------------------------------------------------------------------------
"  AUTOCOMMANDS
" -------------------------------------------------------------------------------------------

call ConfigInc('autocmds.vim')

" -------------------------------------------------------------------------------------------
"  PLUGINS
" -------------------------------------------------------------------------------------------

call ConfigInc('plugins.vim')

" Map vim-plug most used functions
nnoremap <localleader>pu :PlugUpdate<cr>
nnoremap <localleader>pc :PlugClean<cr>
nnoremap <localleader>pi :PlugInstall<cr>

" *******************************************************************
" Plugins with many lines of configuration are under 'plugins' folder
" *******************************************************************

" elzr/vim-json
" ==================================
let g:vim_json_syntax_conceal = 0

" posva/vim-vue
" ==================================
let g:vue_disable_pre_processors = 1

" slashmili/alchemist.vim
" ==================================
let g:alchemist_tag_disable = 1 "Use Universal ctags instead
let g:alchemist_mappings_disable = 1

" ditmammoth/doorboy.vim
" ==================================
" Easy jump closings without leaving home row or insert mode
inoremap ii <esc>la

" mattn/emmet-vim
" ==================================
let g:user_emmet_mode='a'
let g:user_emmet_install_global = 0
let g:user_emmet_leader_key='º' " Hack gor using 1 key as leader
autocmd FileType html,css,scss,vue,jsx,javascript,javascript.jsx,gtpl
            \ EmmetInstall
            \ | imap <buffer> <C-Return> <Plug>(emmet-expand-abbr)

" junegunn/vim-easy-align
" ==================================
xmap ga <Plug>(EasyAlign)
nmap ga <Plug>(EasyAlign)

" Yggdroot/indentLine
" ==================================
let g:indentLine_setColors = 0
let g:indentLine_char = '┆'
let g:indentLine_color_gui = '#65737e'

" AndrewRadev/splitjoin.vim
" ==================================
let g:splitjoin_split_mapping = ''
let g:splitjoin_join_mapping = ''
nmap <localleader>j :SplitjoinSplit<CR>
nmap <localleader>k :SplitjoinJoin<CR>

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

" scrooloose/nerdtree
" ==================================
" map <leader>n :NERDTreeToggle<cr>
" map <leader>b :NERDTreeFind<cr>
" let g:NERDTreeShowHidden = 1
" let g:NERDTreeAutoDeleteBuffer = 1
" let g:NERDTreeCascadeOpenSingleChildDir = 1
" let g:NERDTreeQuitOnOpen = 1

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

" lotabout/skim
" ==================================
" nnoremap <C-s> :<C-u>SK --color=selected:238,current_match:214<cr>

" AndrewRadev/switch.vim
" ==================================
let g:switch_mapping = ""
noremap <leader>s :Switch<cr>

" christoomey/vim-tmux-navigator
" ==================================
let g:tmux_navigator_no_mappings = 1
noremap <silent> <C-h> :TmuxNavigateLeft<cr>
noremap <silent> <C-j> :TmuxNavigateDown<cr>
noremap <silent> <C-k> :TmuxNavigateUp<cr>
noremap <silent> <C-l> :TmuxNavigateRight<cr>
noremap <silent> <C-p> :TmuxNavigatePrevious<cr>

" hauleth/sad.vim
" ==================================
nmap <leader>c <Plug>(sad-change-forward)
vmap <leader>c <Plug>(sad-change-forward)
nmap <leader>C <Plug>(sad-change-backward)
vmap <leader>C <Plug>(sad-change-backward)

" matze/vim-move
" ==================================
" Using a hack here, this rare signs are equal as pressing <ALT-j> and <ALT-k>
" Don't know why alt key is not working without this weird mappings
nmap ¶ <Plug>MoveLineDown
vmap ¶ <Plug>MoveBlockDown
nmap § <Plug>MoveLineUp
vmap § <Plug>MoveBlockUp

" rizzatti/dash.vim
" ==================================
nmap <silent> <C-d> <Plug>DashSearch

" airblade/vim-rooter
" ==================================
nnoremap <localleader>cd :Rooter<cr>
let g:rooter_manual_only = 1
let g:rooter_patterns = ['Gemfile', 'mix.exs', 'package.json', '*.yml', '*.yaml', '.git/', 'node_modules/', '.hg/', '.gitignore']
let g:rooter_change_directory_for_non_project_files = ''

" deoplete
" ==================================
let g:deoplete#enable_at_startup = 1
call deoplete#custom#option('keyword_patterns', {'clojure': '[\w!$%&*+/:<=>?@\^_~\-\.#]*'})
set completeopt-=preview

" float-preview
" =================================
let g:float_preview#docked = 0
let g:float_preview#max_width = 80
let g:float_preview#max_height = 40

" carlitux/deoplete-ternjs
" ==================================
let g:tern_request_timeout = 1
let g:tern_show_signature_in_pum = 1
let g:deoplete#sources#ternjs#timeout = 1
let g:deoplete#sources#ternjs#tern_bin = '/usr/local/bin/tern'
" let g:deoplete#sources#ternjs#types = 1
" let g:deoplete#sources#ternjs#docs = 1
let g:deoplete#sources#ternjs#filetypes = [
  \ 'javascript',
  \ 'vue',
  \ 'jsx',
  \ 'javascript.jsx'
\ ]

" zchee/deoplete-go
" ==================================
let g:deoplete#sources#go#gocode_binary = $GOPATH . '/bin/gocode'

" racer-rust/vim-racer
" ==================================
let g:racer_cmd = '~/.cargo/bin/racer'
let g:racer_experimental_completer = 1

" wellle/tmux-complete.vim
" ==================================
let g:tmuxcomplete#trigger = ''

" Shougo/neosnippet
" ==================================
imap <C-k> <Plug>(neosnippet_expand_or_jump)
smap <C-k> <Plug>(neosnippet_expand_or_jump)
xmap <C-k> <Plug>(neosnippet_expand_target)

" Shougo/echodoc.vim
" ==================================
let g:echodoc#enable_at_startup = 1

" vim-airline/vim-airline
" ==================================
let g:airline#extensions#tabline#enabled = 1
let g:airline#extensions#tabline#fnamemod = ':t'
let g:airline#extensions#tabline#buffer_nr_format = '%s '
let g:airline#extensions#tabline#buffer_nr_show = 1
let g:airline_powerline_fonts = 1
let g:airline_enable_branch = 1
let g:airline_branch_prefix = '⎇ '
let g:airline_skip_empty_sections = 1
" let g:airline_theme='oceanicnext'
let g:airline#extensions#ale#enabled = 1

" itchyny/lightline.vim
" ===================================
let g:lightline = {
      \ 'colorscheme': 'seoul256',
      \ }


" itmammoth/doorboy.vim
" ===================================
let g:doorboy_nomap_quotations = {
  \ 'clojure': ["'"]
  \ }

" luochen1990/rainbow
" ===================================
let g:rainbow_active = 1 " adds color to my ()


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

" vim-clap 
" ===================================

let g:clap_provider_grep_delay = 50
let g:clap_provider_grep_opts = '-H --no-heading --vimgrep --smart-case --hidden -g "!.git/"'


nnoremap <space>* :Clap grep ++query=<cword><cr>
nnoremap <leader>fg :Clap grep<cr>
nnoremap <leader>ff :Clap files --hidden<cr>
nnoremap <leader>fb :Clap buffers<cr>
nnoremap <leader>fw :Clap windows<cr>
nnoremap <leader>fr :Clap history<cr>
nnoremap <leader>fh :Clap command_history<cr>
nnoremap <leader>fj :Clap jumps<cr>
nnoremap <leader>fl :Clap blines<cr>
nnoremap <leader>fL :Clap lines<cr>
nnoremap <leader>ft :Clap filetypes<cr>
nnoremap <leader>fm :Clap marks<cr>


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
nnoremap <leader>Nn :Find <CR>

" -------------------------------------------------------------------------------------------
"  FUNCTIONS
" -------------------------------------------------------------------------------------------

call ConfigInc('functions.vim')

"----------------------------------------------------------------------------------------------
" KEYBINDINGS
"----------------------------------------------------------------------------------------------

call ConfigInc('keybindings.vim')

"----------------------------------------------------------------------------------------------
" THEMES / COLORS / UI
"----------------------------------------------------------------------------------------------

" If colorscheme = onehalfdark
" colorscheme onehalfdark
" highlight CursorLineNr guifg=#fac863

" If colorscheme = Nord
colorscheme nord
highlight CursorLineNr guifg=#5E81AC

" If colorscheme = nova
" colorscheme nova
" highlight CursorLineNr guifg=#f2c38f

" If colorscheme = Seoul256
" let g:seoul256_background = 233
" set background=dark
" colorscheme seoul256
