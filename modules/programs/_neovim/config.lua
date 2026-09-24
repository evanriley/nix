vim.opt.complete = { 'o', '.', 'w', 'b' }
vim.opt.listchars = { tab = '  ', trail = '.', nbsp = '+' }
vim.opt.jumpoptions:append('view')

-- Colors follow the desktop: ~/.config/theme/mode is generated per
-- light/dark generation, and apply-theme sends SIGUSR1 after switching.
local function desktop_mode()
  local file = io.open(vim.fn.expand('~/.config/theme/mode'), 'r')
  if not file then return 'dark' end
  local mode = vim.trim(file:read('*a'))
  file:close()
  return mode == 'light' and 'light' or 'dark'
end

local function apply_desktop_mode()
  vim.schedule(function()
    local mode = desktop_mode()
    vim.o.background = mode
    vim.cmd.source(vim.fn.fnameescape(
      vim.g.monobiome_themes .. '/alpine-monobiome-' .. mode .. '.theme.vim'))
  end)
end

apply_desktop_mode()
vim.api.nvim_create_autocmd('Signal', { pattern = 'SIGUSR1', callback = apply_desktop_mode })

vim.api.nvim_create_autocmd('User', {
  pattern = 'Parinfer',
  callback = function()
    vim.b.minipairs_disable = vim.b.parinfer_enabled == true or vim.b.parinfer_enabled == 1
  end,
})

require('mini.icons').tweak_lsp_kind()

local snippets = require('mini.snippets')
snippets.setup({ snippets = { snippets.gen_loader.from_lang() } })

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

vim.keymap.set('n', '<leader>sh', swap_buf('h'), { desc = 'Swap buffer h' })
vim.keymap.set('n', '<leader>sj', swap_buf('j'), { desc = 'Swap buffer j' })
vim.keymap.set('n', '<leader>sk', swap_buf('k'), { desc = 'Swap buffer k' })
vim.keymap.set('n', '<leader>sl', swap_buf('l'), { desc = 'Swap buffer l' })

vim.lsp.config('*', { root_markers = { '.git' } })
vim.lsp.config('gleam', { root_markers = { 'gleam.toml' } })
vim.lsp.config('zls', { settings = { zls = { enable_build_on_save = true } } })
-- Servers come from each project's development shell.
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
      term_win = vim.api.nvim_open_win(term_buf, true, { split = 'below', height = 15 })
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
      return vim.fn.input('Executable: ', workflow.root() .. '/zig-out/bin/', 'file')
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
vim.keymap.set('n', '<leader>k', function() MiniBufremove.delete(0, false) end, { desc = 'Kill buffer' })
vim.keymap.set('n', '<leader>xd', vim.diagnostic.setqflist, { desc = 'Diagnostics to quickfix' })

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
