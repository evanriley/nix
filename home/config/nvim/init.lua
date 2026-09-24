vim.g.mapleader = ' '
vim.g.maplocalleader = ','

vim.o.number = true
vim.o.relativenumber = true
vim.o.signcolumn = 'yes'
vim.o.cursorline = true
vim.o.expandtab = true
vim.o.shiftwidth = 2
vim.o.tabstop = 2
vim.o.smartindent = true
vim.o.wrap = false
vim.o.linebreak = true
vim.o.ignorecase = true
vim.o.smartcase = true
vim.o.undofile = true
vim.o.splitright = true
vim.o.splitbelow = true
vim.o.splitkeep = 'screen'
vim.o.termguicolors = true
vim.o.winborder = 'rounded'
vim.o.smoothscroll = true
vim.o.confirm = true
vim.o.inccommand = 'split'
vim.o.updatetime = 250
vim.o.timeoutlen = 300
vim.o.completeopt = 'menuone,noselect,popup,fuzzy'
vim.o.autocomplete = true
vim.o.autocompletedelay = 100
vim.opt.complete = { 'o', '.', 'w', 'b' }
vim.o.foldmethod = 'expr'
vim.o.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
vim.o.foldlevelstart = 99
vim.o.foldlevel = 99
vim.o.pumheight = 10
vim.o.scrolloff = 8
vim.o.sidescrolloff = 8
vim.o.mouse = 'a'
vim.o.list = true
vim.opt.listchars = { tab = '  ', trail = '.', nbsp = '+' }
vim.opt.jumpoptions:append('view')
vim.o.clipboard = 'unnamedplus'
vim.o.showmode = false
vim.o.showtabline = 2
vim.o.laststatus = 3

vim.g['conjure#filetypes'] = { 'clojure' }
vim.g.parinfer_filetypes = { 'clojure' }
vim.g.parinfer_no_maps = true

vim.api.nvim_create_autocmd('PackChanged', {
  callback = function(ev)
    if ev.data.kind ~= 'install' and ev.data.kind ~= 'update' then return end

    local name = ev.data.spec.name
    if name == 'nvim-treesitter' then
      if not ev.data.active then vim.cmd.packadd('nvim-treesitter') end
      vim.cmd('TSUpdate')
    end
  end,
})

vim.pack.add({
  'https://github.com/endofunctorio/monobiome',
  'https://github.com/nvim-treesitter/nvim-treesitter',
  'https://github.com/RRethy/nvim-treesitter-endwise',
  'https://github.com/nvim-mini/mini.nvim',
  'https://github.com/neovim/nvim-lspconfig',
  'https://codeberg.org/mfussenegger/nvim-dap',
  'https://github.com/rafamadriz/friendly-snippets',
  'https://github.com/stevearc/oil.nvim',
  'https://github.com/Olical/conjure',
  'https://github.com/gpanders/nvim-parinfer',
  'https://github.com/MeanderingProgrammer/render-markdown.nvim',
  'https://github.com/mbbill/undotree',
}, {
  confirm = false,
})

local function setup(name, opts)
  require(name).setup(opts or {})
end

local function desktop_mode()
  local path = vim.fn.expand('~/.config/theme/mode')
  local file = io.open(path, 'r')
  if not file then return 'dark' end
  local mode = vim.trim(file:read('*a'))
  file:close()
  return mode == 'light' and 'light' or 'dark'
end

local function apply_desktop_mode()
  vim.schedule(function()
    local mode = desktop_mode()
    vim.o.background = mode
    local theme = vim.fn.stdpath('data')
      .. '/site/pack/core/opt/monobiome/app-config/nvim/alpine-monobiome-'
      .. mode .. '.theme.vim'
    vim.cmd.source(vim.fn.fnameescape(theme))
  end)
end

apply_desktop_mode()
vim.api.nvim_create_autocmd('Signal', {
  pattern = 'SIGUSR1',
  callback = apply_desktop_mode,
})

setup('oil', { default_file_explorer = true })
setup('render-markdown')

setup('mini.input')
setup('mini.sessions', { autoread = false, autowrite = false, file = '' })
setup('mini.ai')
setup('mini.bracketed')
setup('mini.bufremove')
setup('mini.diff')
setup('mini.extra')
setup('mini.git')
setup('mini.jump')
setup('mini.jump2d')
setup('mini.move', {
  mappings = {
    left = '<M-Left>', right = '<M-Right>', down = '<M-Down>', up = '<M-Up>',
    line_left = '<M-Left>', line_right = '<M-Right>',
    line_down = '<M-Down>', line_up = '<M-Up>',
  },
})
setup('mini.notify')
setup('mini.pairs')
vim.api.nvim_create_autocmd('User', {
  pattern = 'Parinfer',
  callback = function()
    vim.b.minipairs_disable = vim.b.parinfer_enabled == true or vim.b.parinfer_enabled == 1
  end,
})
setup('mini.pick')
setup('mini.statusline', { use_icons = true })
setup('mini.surround')
setup('mini.tabline')
setup('mini.trailspace')

local icons = require('mini.icons')
icons.setup()
icons.tweak_lsp_kind()

vim.notify = require('mini.notify').make_notify()

local snippets = require('mini.snippets')
snippets.setup({
  snippets = { snippets.gen_loader.from_lang() },
})

vim.keymap.set('i', '<C-Space>', '<C-x><C-o>', { desc = 'LSP completion' })
vim.keymap.set('i', '<M-Space>', function()
  return (vim.fn.pumvisible() == 1 and '<C-e>' or '') .. '<C-x><C-n>'
end, { expr = true, desc = 'Current buffer word completion' })

local pick = require('mini.pick')
local extra = require('mini.extra')
local workflow = require('workflow')
workflow.setup()

local function swap_buf(dir)
  return function()
    local cur_win = vim.api.nvim_get_current_win()
    vim.cmd.wincmd(dir)
    local target_win = vim.api.nvim_get_current_win()
    if target_win == cur_win then return end
    local cur_buf = vim.api.nvim_win_get_buf(cur_win)
    vim.api.nvim_win_set_buf(cur_win, vim.api.nvim_win_get_buf(target_win))
    vim.api.nvim_win_set_buf(target_win, cur_buf)
    vim.api.nvim_set_current_win(cur_win)
  end
end

vim.keymap.set('n', '<A-h>', '<Cmd>vertical resize -2<CR>')
vim.keymap.set('n', '<A-j>', '<Cmd>resize +2<CR>')
vim.keymap.set('n', '<A-k>', '<Cmd>resize -2<CR>')
vim.keymap.set('n', '<A-l>', '<Cmd>vertical resize +2<CR>')
vim.keymap.set('n', '<C-h>', '<C-w>h')
vim.keymap.set('n', '<C-j>', '<C-w>j')
vim.keymap.set('n', '<C-k>', '<C-w>k')
vim.keymap.set('n', '<C-l>', '<C-w>l')
vim.keymap.set('n', '<C-\\>', '<C-w>p')
vim.keymap.set('n', '<leader>sh', swap_buf('h'), { desc = 'Swap buffer h' })
vim.keymap.set('n', '<leader>sj', swap_buf('j'), { desc = 'Swap buffer j' })
vim.keymap.set('n', '<leader>sk', swap_buf('k'), { desc = 'Swap buffer k' })
vim.keymap.set('n', '<leader>sl', swap_buf('l'), { desc = 'Swap buffer l' })

vim.keymap.set('n', '<leader>m', '<Cmd>RenderMarkdown toggle<CR>', { desc = 'Toggle markdown render' })

vim.keymap.set('n', '-', '<CMD>Oil<CR>', { desc = 'Open parent directory' })

local treesitter = require('nvim-treesitter')
local treesitter_languages = {
  'bash', 'c', 'clojure', 'cpp', 'fish', 'gleam', 'lua', 'markdown', 'markdown_inline',
  'ocaml', 'ocaml_interface', 'python', 'rust', 'vimdoc', 'zig',
}
treesitter.setup()
treesitter.install(treesitter_languages)
vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'sh', 'bash', 'c', 'clojure', 'cpp', 'fish', 'gleam', 'help', 'lua', 'markdown', 'ocaml', 'ocamlinterface', 'python', 'rust', 'zig' },
  callback = function()
    if not pcall(vim.treesitter.start) then return end
    if vim.bo.filetype ~= 'clojure' and vim.bo.filetype ~= 'help' then
      vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
    end
  end,
})

vim.lsp.config('*', { root_markers = { '.git' } })
vim.lsp.config('gleam', { root_markers = { 'gleam.toml' } })
vim.lsp.config('zls', {
  settings = {
    zls = {
      enable_build_on_save = true,
    },
  },
})
vim.lsp.enable({ 'rust_analyzer', 'ruff', 'zls', 'clangd', 'clojure_lsp', 'gleam', 'lua_ls', 'ocamllsp' })

vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('lsp-attach', {}),
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if not client then return end
    local buf = args.buf

    if client:supports_method('textDocument/completion') then
      vim.lsp.completion.enable(true, client.id, buf, { autotrigger = false })
      vim.bo[buf].omnifunc = 'v:lua.vim.lsp.omnifunc'
    end

    local map = function(mode, lhs, rhs, desc)
      vim.keymap.set(mode, lhs, rhs, { buffer = buf, desc = desc })
    end
    map('n', 'gd', vim.lsp.buf.definition, 'Go to definition')
    map('n', '<leader>f', function() workflow.format(buf) end, 'Format buffer')
    map('n', '<leader>e', vim.diagnostic.open_float, 'Show diagnostic')
  end,
})

snippets.start_lsp_server({ match = false })

vim.keymap.set('i', '<Tab>', function()
  if vim.fn.pumvisible() == 1 then
    return '<C-n>'
  elseif snippets.session.get() then
    return '<Cmd>lua MiniSnippets.session.jump("next")<CR>'
  elseif vim.snippet.active({ direction = 1 }) then
    return '<Cmd>lua vim.snippet.jump(1)<CR>'
  elseif vim.b.parinfer_enabled == true or vim.b.parinfer_enabled == 1 then
    return '<Plug>(parinfer-tab)'
  else
    return '<Tab>'
  end
end, { expr = true })

vim.keymap.set('i', '<S-Tab>', function()
  if vim.fn.pumvisible() == 1 then
    return '<C-p>'
  elseif snippets.session.get() then
    return '<Cmd>lua MiniSnippets.session.jump("prev")<CR>'
  elseif vim.snippet.active({ direction = -1 }) then
    return '<Cmd>lua vim.snippet.jump(-1)<CR>'
  elseif vim.b.parinfer_enabled == true or vim.b.parinfer_enabled == 1 then
    return '<Plug>(parinfer-backtab)'
  else
    return '<S-Tab>'
  end
end, { expr = true })

vim.keymap.set('i', '<CR>', function()
  if vim.fn.pumvisible() == 1 and vim.fn.complete_info().selected ~= -1 then
    return vim.keycode('<C-y>')
  end
  return MiniPairs.cr()
end, { expr = true, replace_keycodes = false })

vim.diagnostic.config({
  virtual_text = { spacing = 4, prefix = '' },
  signs = true,
  underline = true,
  update_in_insert = false,
})

local term_buf, term_win = nil, nil
local function toggle_terminal()
  if term_win and vim.api.nvim_win_is_valid(term_win) then
    vim.api.nvim_win_hide(term_win)
    term_win = nil
  else
    if term_buf and vim.api.nvim_buf_is_valid(term_buf) then
      term_win = vim.api.nvim_open_win(term_buf, true, {
        split = 'below', height = 15,
      })
    else
      vim.cmd('botright 15split | terminal')
      term_buf = vim.api.nvim_get_current_buf()
      term_win = vim.api.nvim_get_current_win()
      vim.bo[term_buf].buflisted = false
    end
    vim.cmd('startinsert')
  end
end
vim.keymap.set('n', '<leader>t', toggle_terminal, { desc = 'Toggle terminal' })

local function zig_root() return workflow.root() end

vim.keymap.set('n', '<leader>zb', function() workflow.run('build') end, { desc = 'Project build' })
vim.keymap.set('n', '<leader>zt', function() workflow.run('test') end, { desc = 'Project test' })
vim.keymap.set('n', '<leader>zf', function() workflow.run('test_file') end, { desc = 'Test current file' })

local dap = require('dap')
dap.adapters.lldb = {
  type = 'executable',
  command = vim.fn.exepath('lldb-dap'),
  name = 'lldb',
}
dap.configurations.zig = {
  {
    name = 'Launch Zig executable',
    type = 'lldb',
    request = 'launch',
    cwd = '${workspaceFolder}',
    stopOnEntry = false,
    program = function()
      return vim.fn.input('Executable: ', zig_root() .. '/zig-out/bin/', 'file')
    end,
  },
}

vim.keymap.set('n', '<leader>db', dap.toggle_breakpoint, { desc = 'Debug toggle breakpoint' })
vim.keymap.set('n', '<leader>dc', dap.continue, { desc = 'Debug continue' })
vim.keymap.set('n', '<leader>di', dap.step_into, { desc = 'Debug step into' })
vim.keymap.set('n', '<leader>dn', dap.step_over, { desc = 'Debug step over' })
vim.keymap.set('n', '<leader>do', dap.step_out, { desc = 'Debug step out' })
vim.keymap.set('n', '<leader>dr', dap.repl.open, { desc = 'Debug REPL' })
vim.keymap.set('n', '<leader>dt', dap.terminate, { desc = 'Debug terminate' })

vim.keymap.set('n', '<leader><leader>', function() pick.builtin.files(nil, { source = { cwd = workflow.root() } }) end, { desc = 'Find project files' })
vim.keymap.set('n', '<leader>/', function() pick.builtin.grep_live(nil, { source = { cwd = workflow.root() } }) end, { desc = 'Grep project' })
vim.keymap.set('n', '<leader>b', pick.builtin.buffers, { desc = 'Buffers' })
vim.keymap.set('n', '<leader>h', pick.builtin.help, { desc = 'Help' })
vim.keymap.set('n', '<leader>r', pick.builtin.resume, { desc = 'Resume picker' })
vim.keymap.set('n', '<leader>o', extra.pickers.oldfiles, { desc = 'Recent files' })
vim.keymap.set('n', '<leader>g', function() extra.pickers.git_files(nil, { source = { cwd = workflow.root() } }) end, { desc = 'Git project files' })
vim.keymap.set('n', '<leader>q', extra.pickers.list, { desc = 'Lists' })

vim.keymap.set('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })
vim.keymap.set('n', '<Esc>', '<Cmd>nohlsearch<CR>', { desc = 'Clear search highlight' })
vim.keymap.set('n', '<leader>w', '<Cmd>w<CR>', { desc = 'Save file' })
vim.keymap.set('n', '<leader>k', function() MiniBufremove.delete(0, false) end, { desc = 'Kill buffer' })
vim.keymap.set('n', '<leader>xd', vim.diagnostic.setqflist, { desc = 'Diagnostics to quickfix' })
vim.keymap.set('n', '<leader>u', '<Cmd>UndotreeToggle<CR>', { desc = 'Toggle undotree' })
vim.keymap.set('n', '<leader>cw', '<Cmd>lua MiniTrailspace.trim()<CR>', { desc = 'Trim trailing whitespace' })
vim.keymap.set('n', '<leader>G', '<Cmd>botright 15split | terminal lazygit<CR>', { desc = 'Lazygit' })

vim.api.nvim_create_autocmd('TextYankPost', {
  group = vim.api.nvim_create_augroup('yank-highlight', {}),
  callback = function() vim.hl.on_yank({ timeout = 200 }) end,
})

local clue = require('mini.clue')
clue.setup({
  triggers = {
    { mode = { 'n', 'x' }, keys = '<Leader>' },
    { mode = 'n', keys = '[' },
    { mode = 'n', keys = ']' },
    { mode = 'i', keys = '<C-x>' },
    { mode = { 'n', 'x' }, keys = 'g' },
    { mode = { 'n', 'x' }, keys = "'" },
    { mode = { 'n', 'x' }, keys = '`' },
    { mode = { 'n', 'x' }, keys = '"' },
    { mode = { 'i', 'c' }, keys = '<C-r>' },
    { mode = 'n', keys = '<C-w>' },
    { mode = { 'n', 'x' }, keys = 'z' },
  },
  clues = {
    clue.gen_clues.square_brackets(),
    clue.gen_clues.builtin_completion(),
    clue.gen_clues.g(),
    clue.gen_clues.marks(),
    clue.gen_clues.registers(),
    clue.gen_clues.windows(),
    clue.gen_clues.z(),
  },
})
