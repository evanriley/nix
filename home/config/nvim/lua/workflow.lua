local M = {}
local jobs = {}
local markers = { 'build.zig', 'build.zig.zon', 'gleam.toml', 'dune-project', 'dune-workspace', 'deps.edn', 'bb.edn', 'project.clj', '.git' }

function M.root(buf)
  buf = buf or 0
  local name = vim.api.nvim_buf_get_name(buf)
  if vim.bo[buf].buftype ~= '' or name == '' then return vim.fn.getcwd() end
  return vim.fs.root(buf, markers) or vim.fs.dirname(name)
end

local function inside(path, root)
  return path == root or path:sub(1, #root + 1) == root .. '/'
end

function M.save_project(root)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == '' and vim.bo[buf].modified
      and inside(vim.api.nvim_buf_get_name(buf), root) then
      vim.api.nvim_buf_call(buf, function() vim.cmd.update() end)
    end
  end
end

function M.command(action, buf)
  buf = buf or 0
  local root, ft = M.root(buf), vim.bo[buf].filetype
  local custom = vim.b[buf].project_commands
  if custom and custom[action] then return vim.deepcopy(custom[action]), root end
  if ft == 'zig' or vim.uv.fs_stat(root .. '/build.zig') then
    local commands = { build = { 'zig', 'build' }, test = { 'zig', 'build', 'test' },
      run = { 'zig', 'build', 'run' }, test_file = { 'zig', 'test', vim.api.nvim_buf_get_name(buf) } }
    if commands[action] then return commands[action], root end
  elseif ft == 'gleam' or vim.uv.fs_stat(root .. '/gleam.toml') then
    local commands = { build = { 'gleam', 'build' }, test = { 'gleam', 'test' }, run = { 'gleam', 'run' } }
    if commands[action] then return commands[action], root end
  elseif ft == 'ocaml' or ft == 'ocamlinterface' or ft == 'dune' or vim.uv.fs_stat(root .. '/dune-project') then
    local commands = { build = { 'dune', 'build' }, test = { 'dune', 'runtest' }, run = { 'dune', 'exec' },
      watch = { 'dune', 'build', '--watch' }, repl = { 'dune', 'utop' } }
    local cmd = commands[action]
    if cmd then
      if vim.fn.executable('opam') == 1 then cmd = vim.list_extend({ 'opam', 'exec', '--' }, cmd) end
      return cmd, root
    end
  end
  error('No ' .. action .. ' command for this project; set b:project_commands.' )
end

function M.diagnostics(output, root)
  local result = {}
  for line in (output .. '\n'):gmatch('(.-)\n') do
    line = line:gsub('\27%[[%d;]*m', ''):gsub('\r$', '')
    if line ~= '' then
      local file, row, col, message = line:match('^(.+):(%d+):(%d+):%s*(.*)$')
      if not file then
        file, row, col = line:match('^File "(.-)", line (%d+), characters (%d+)%-%d+:')
        if file then col, message = tonumber(col) + 1, line end
      end
      if file then
        if file:sub(1, 1) ~= '/' then file = root .. '/' .. file end
        table.insert(result, { filename = file, lnum = tonumber(row), col = tonumber(col), text = message })
      else
        table.insert(result, { text = line, valid = 0 })
      end
    end
  end
  return result
end

function M.execute(cmd, root, action)
  if jobs[root] then error('A build/test is already running in ' .. root) end
  M.save_project(root)
  if action == 'run' or action == 'watch' or action == 'repl' then
    vim.cmd('botright 15split')
    vim.cmd.enew()
    local id = vim.fn.jobstart(cmd, { cwd = root, term = true })
    if id <= 0 then error('Could not start ' .. cmd[1]) end
    vim.cmd.startinsert()
    return
  end
  local title = vim.fs.basename(root) .. ': ' .. table.concat(cmd, ' ')
  vim.fn.setqflist({}, ' ', { title = title .. ' (running)', items = {} })
  local qfid = vim.fn.getqflist({ id = 0 }).id
  local process = vim.system(cmd, { cwd = root, text = true }, function(result)
    vim.schedule(function()
      jobs[root] = nil
      local output = (result.stdout or '') .. '\n' .. (result.stderr or '')
      vim.fn.setqflist({}, 'r', { id = qfid, title = title .. ' [exit ' .. result.code .. ']',
        items = M.diagnostics(output, root) })
      vim.notify(title .. ': exit ' .. result.code, result.code == 0 and vim.log.levels.INFO or vim.log.levels.WARN)
      if result.code ~= 0 and vim.fn.getqflist({ id = 0 }).id == qfid then vim.cmd.copen() end
    end)
  end)
  jobs[root] = process
end

function M.run(action)
  local cmd, root = M.command(action)
  if action == 'run' and cmd[#cmd] == 'exec' then
    vim.ui.input({ prompt = 'Dune executable (e.g. bin/main.exe): ' }, function(executable)
      if not executable or executable == '' then return end
      table.insert(cmd, executable)
      M.execute(cmd, root, action)
    end)
    return
  end
  M.execute(cmd, root, action)
end

local preferred = { zig = 'zls', clojure = 'clojure_lsp', gleam = 'gleam', ocaml = 'ocamllsp',
  ocamlinterface = 'ocamllsp', python = 'ruff', lua = 'lua_ls', c = 'clangd', cpp = 'clangd', rust = 'rust_analyzer' }

function M.formatter(buf)
  local clients = vim.lsp.get_clients({ bufnr = buf, method = 'textDocument/formatting' })
  local name = vim.b[buf].format_client or preferred[vim.bo[buf].filetype]
  for _, client in ipairs(clients) do if client.name == name then return client end end
  if #clients == 1 and not vim.b[buf].format_client then return clients[1] end
end

function M.format(buf, quiet)
  buf = buf or vim.api.nvim_get_current_buf()
  local client = M.formatter(buf)
  if not client then
    if not quiet then vim.notify('No unambiguous formatter; set b:format_client.', vim.log.levels.WARN) end
    return
  end
  vim.lsp.buf.format({ bufnr = buf, id = client.id, timeout_ms = 3000 })
end

function M.setup()
  local map = function(lhs, fn, desc, mode) vim.keymap.set(mode or 'n', '<leader>' .. lhs, fn, { desc = desc }) end
  for key, action in pairs({ b = 'build', t = 'test', T = 'test_file', r = 'run', W = 'watch', u = 'repl' }) do
    map('c' .. key, function() M.run(action) end, 'Project ' .. action)
  end
  map('cn', '<Cmd>cnext<CR>', 'Next compiler diagnostic')
  map('cp', '<Cmd>cprevious<CR>', 'Previous compiler diagnostic')
  map('cq', '<Cmd>copen<CR>', 'Build output / quickfix')
  map('cs', function() require('mini.extra').pickers.lsp({ scope = 'document_symbol' }) end, 'Document symbols')
  map('cS', function() require('mini.extra').pickers.lsp({ scope = 'workspace_symbol_live' }) end, 'Workspace symbols')
  map('cD', function() require('mini.extra').pickers.diagnostic() end, 'Diagnostics picker')
  map('ca', vim.lsp.buf.code_action, 'Code action', { 'n', 'x' })
  map('cR', vim.lsp.buf.rename, 'Rename symbol')
  map('ce', function() vim.lsp.buf.selection_range(1) end, 'Expand selection', 'x')
  map('cE', function() vim.lsp.buf.selection_range(-1) end, 'Shrink selection', 'x')
  map('vi', function()
    vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = 0 }), { bufnr = 0 })
  end, 'Toggle inlay hints')
  map('vd', function()
    local enabled = not vim.diagnostic.config().virtual_lines
    vim.diagnostic.config({ virtual_lines = enabled and { current_line = true } or false,
      virtual_text = not enabled and { spacing = 4, prefix = '' } or false })
  end, 'Toggle diagnostic lines')
  map('vf', function()
    vim.b.format_on_save = vim.b.format_on_save == false
    vim.notify('Format on save: ' .. (vim.b.format_on_save and 'on' or 'off'))
  end, 'Toggle buffer format on save')
  map('vz', function() vim.wo.foldenable = not vim.wo.foldenable end, 'Toggle folding')
  map('Sw', function()
    vim.ui.input({ prompt = 'Save session: ', default = vim.fs.basename(M.root()) }, function(name)
      if not name or name == '' then return end
      if not name:match('^[%w_-]+$') then vim.notify('Use letters, numbers, underscore or hyphen.', vim.log.levels.WARN); return end
      require('mini.sessions').write(name)
    end)
  end, 'Save named session')
  map('Sr', function() require('mini.sessions').select('read') end, 'Restore session')
  vim.api.nvim_create_autocmd('BufWritePre', { callback = function(ev)
    if vim.bo[ev.buf].buftype == '' and vim.b[ev.buf].format_on_save ~= false then M.format(ev.buf, true) end
  end })
  local function folds()
    if vim.bo.buftype ~= '' then return end
    local clients = vim.lsp.get_clients({ bufnr = 0, method = 'textDocument/foldingRange' })
    vim.wo.foldexpr = #clients > 0 and 'v:lua.vim.lsp.foldexpr()' or 'v:lua.vim.treesitter.foldexpr()'
  end
  vim.api.nvim_create_autocmd({ 'BufWinEnter', 'LspAttach', 'LspDetach' }, { callback = function() vim.schedule(folds) end })
end

return M
