"----------------------------------------------------------------------------------------------
" KEYBINDINGS
"----------------------------------------------------------------------------------------------

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
