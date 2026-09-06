local uv = vim.uv or vim.loop

local HALF_LIFE = 30 * 24 * 60 * 60
local LAMBDA = math.log(2) / HALF_LIFE
local MAX_STORE_SIZE = 10000

local Frecency = {}
Frecency.__index = Frecency

local function normalize(path)
  if not path or path == "" then
    return nil
  end
  return vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
end

local function load(path)
  if not path or not uv.fs_stat(path) then
    return {}
  end
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return {}
  end
  local decoded_ok, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not decoded_ok or type(decoded) ~= "table" then
    return {}
  end
  local data = {}
  for key, value in pairs(decoded) do
    if type(key) == "string" and type(value) == "number" then
      data[key] = value
    end
  end
  return data
end

function Frecency.new(opts)
  opts = opts or {}
  local path = opts.path
  if path == nil and opts.data == nil then
    path = vim.fn.stdpath("data") .. "/minibuffer/frecency.json"
  end
  return setmetatable({
    data = opts.data or load(path),
    dirty = false,
    max_size = opts.max_size or MAX_STORE_SIZE,
    now = opts.now or os.time,
    path = path,
    stat = opts.stat or uv.fs_stat,
  }, Frecency)
end

function Frecency:to_deadline(score)
  return self.now() + math.log(score) / LAMBDA
end

function Frecency:to_score(deadline)
  return math.exp(LAMBDA * (deadline - self.now()))
end

function Frecency:seed(candidate, value)
  if not (candidate.info or candidate.recent) then
    return 0
  end
  local last_used = type(candidate.info) == "table" and candidate.info.lastused or nil
  if not last_used then
    local stat = self.stat(candidate.path)
    last_used = stat and stat.mtime and stat.mtime.sec or nil
  end
  if not last_used then
    return 0
  end
  return (value or 1) * math.exp(-LAMBDA * (self.now() - last_used))
end

function Frecency:get(candidate, opts)
  opts = opts or {}
  local path = normalize(candidate.path)
  if not path then
    return 0
  end
  local deadline = self.data[path]
  if deadline then
    return self:to_score(deadline)
  end
  return opts.seed == false and 0 or self:seed(candidate)
end

function Frecency:visit(candidate, value)
  local path = normalize(candidate.path)
  if not path then
    return
  end
  local score = self:get(candidate, { seed = false }) + (value or 1)
  self.data[path] = self:to_deadline(score)
  self.dirty = true
end

function Frecency:_trim()
  local entries = {}
  for path, deadline in pairs(self.data) do
    entries[#entries + 1] = { path = path, deadline = deadline }
  end
  if #entries <= self.max_size then
    return
  end
  table.sort(entries, function(left, right)
    return left.deadline > right.deadline
  end)
  local data = {}
  for index = 1, self.max_size do
    data[entries[index].path] = entries[index].deadline
  end
  self.data = data
end

function Frecency:save()
  if not self.path or not self.dirty then
    return true
  end
  self:_trim()
  vim.fn.mkdir(vim.fs.dirname(self.path), "p")
  local temporary = ("%s.%d.tmp"):format(self.path, uv.os_getpid())
  local file, open_error = uv.fs_open(temporary, "w", 384)
  if not file then
    return nil, open_error
  end
  local ok, write_error = uv.fs_write(file, vim.json.encode(self.data), -1)
  uv.fs_close(file)
  if not ok then
    uv.fs_unlink(temporary)
    return nil, write_error
  end
  local renamed, rename_error = uv.fs_rename(temporary, self.path)
  if not renamed and uv.fs_stat(self.path) then
    uv.fs_unlink(self.path)
    renamed, rename_error = uv.fs_rename(temporary, self.path)
  end
  if not renamed then
    uv.fs_unlink(temporary)
    return nil, rename_error
  end
  self.dirty = false
  return true
end

local M = {}
local default_store
local setup = false

local function visit_buf(buf)
  if
    not vim.api.nvim_buf_is_valid(buf)
    or vim.bo[buf].buftype ~= ""
    or not vim.bo[buf].buflisted
  then
    return
  end
  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" or not uv.fs_stat(path) then
    return
  end
  default_store:visit({ path = path, info = vim.fn.getbufinfo(buf)[1] })
end

local function initialize()
  if setup then
    return
  end
  setup = true
  local group = vim.api.nvim_create_augroup("minibuffer_frecency", { clear = true })
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    callback = function(event)
      local win = vim.api.nvim_get_current_win()
      if
        vim.api.nvim_win_is_valid(win)
        and vim.api.nvim_win_get_config(win).relative == ""
      then
        visit_buf(event.buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd("ExitPre", {
    group = group,
    callback = function()
      local ok, err = default_store:save()
      if not ok then
        vim.notify(
          "[minibuffer] Failed to save frecency: " .. tostring(err),
          vim.log.levels.WARN
        )
      end
    end,
  })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    visit_buf(buf)
  end
end

function M.new(opts)
  return Frecency.new(opts)
end

function M.default()
  if not default_store then
    default_store = Frecency.new()
  end
  initialize()
  return default_store
end

return M
