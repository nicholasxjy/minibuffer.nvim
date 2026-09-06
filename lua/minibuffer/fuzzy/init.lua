local Score = require("minibuffer.fuzzy.score")

---@class minibuffer.fuzzy.Candidate
---@field text string Logical text used for matching
---@field path? string Normalized absolute file path
---@field display? string Formatted text displayed by an adapter
---@field idx? integer Original source index
---@field score? number Score assigned by the latest rank
---@field recent? boolean Whether the file belongs to Neovim's recent files
---@field info? vim.fn.getbufinfo.ret.item Buffer metadata used to seed frecency

---@class minibuffer.fuzzy.Opts
---@field cwd? string
---@field fuzzy? boolean
---@field smartcase? boolean
---@field ignorecase? boolean
---@field filename_bonus? boolean
---@field cwd_bonus? boolean
---@field frecency? boolean|table
---@field history_bonus? boolean
---@field path_separator? string Override the platform separator (primarily for testing)

---@class minibuffer.fuzzy.Ranker
---@field rank fun(self: minibuffer.fuzzy.Ranker, query: string, candidates: minibuffer.fuzzy.Candidate[]): minibuffer.fuzzy.Candidate[]

local Ranker = {}
Ranker.__index = Ranker

local DEFAULT_SCORE = 1000
local SCORE_MATCH = 16
local SCORE_GAP_START = -3
local SCORE_GAP_EXTENSION = -1
local BONUS_BOUNDARY = SCORE_MATCH / 2
local BONUS_CONSECUTIVE = -(SCORE_GAP_START + SCORE_GAP_EXTENSION)
local IS_WINDOWS = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1

local function normalize_path(path)
  path = vim.fs.normalize(path):gsub("\\", "/")
  return IS_WINDOWS and path:lower() or path
end

local function prepare_term(opts, pattern)
  local term = { pattern = pattern, fuzzy = opts.fuzzy ~= false, entropy = 0 }
  for _, file_pattern in ipairs({
    "^(.*[/\\].*):(%d*):(%d*)$",
    "^(.*[/\\].*):(%d*)$",
    "^(.+%.[a-z_]+):(%d*):(%d*)$",
    "^(.+%.[a-z_]+):(%d*)$",
  }) do
    local file = term.pattern:match(file_pattern)
    if file then
      term.field = "file"
      term.pattern = file .. "$"
      break
    end
  end
  if not term.field then
    local field, field_pattern = term.pattern:match("^([%w_][%w_]+):(.*)$")
    if field then
      term.field = field
      term.pattern = field_pattern
    end
  end
  if not term.fuzzy then
    term.entropy = term.entropy + 10
  end
  if term.pattern:sub(1, 1) == "!" then
    term.fuzzy = false
    term.inverse = true
    term.pattern = term.pattern:sub(2)
    term.entropy = term.entropy - 1
  end

  if term.pattern:sub(1, 1) == "'" then
    term.fuzzy = false
    term.pattern = term.pattern:sub(2)
    term.entropy = term.entropy + 10
    if term.pattern:sub(-1) == "'" then
      term.word = true
      term.pattern = term.pattern:sub(1, -2)
      term.entropy = term.entropy + 10
    end
  elseif term.pattern:sub(1, 1) == "^" then
    term.fuzzy = false
    term.exact_prefix = true
    term.pattern = term.pattern:sub(2)
    term.entropy = term.entropy + 20
  end

  if term.pattern:sub(-1) == "$" then
    term.fuzzy = false
    term.exact_suffix = true
    term.pattern = term.pattern:sub(1, -2)
    term.entropy = term.entropy + 20
  end

  local is_lower = term.pattern:lower() == term.pattern
  term.ignorecase = opts.ignorecase ~= false
  if opts.smartcase ~= false then
    term.ignorecase = is_lower
  end
  local rare = #term.pattern:gsub("[%w%s]", "")
  term.entropy = term.entropy + math.min(#term.pattern, 20) + rare * 2
  if not term.ignorecase and not is_lower then
    term.entropy = term.entropy * 2
  end
  if term.ignorecase then
    term.pattern = term.pattern:lower()
  end
  term.chars = {}
  for index = 1, #term.pattern do
    term.chars[index] = term.pattern:sub(index, index)
  end
  return term
end

local function parse_query(opts, query)
  local groups = {}
  local is_or = false
  for part in query:gmatch("%S+") do
    if part == "|" then
      is_or = true
    else
      local term = prepare_term(opts, part)
      if term.pattern ~= "" then
        if is_or and #groups > 0 then
          groups[#groups][#groups[#groups] + 1] = term
        else
          groups[#groups + 1] = { term }
        end
      end
      is_or = false
    end
  end
  for _, alternatives in ipairs(groups) do
    table.sort(alternatives, function(left, right)
      return left.entropy < right.entropy
    end)
  end
  table.sort(groups, function(left, right)
    return left[1].entropy > right[1].entropy
  end)
  return groups
end

local function fuzzy_match_greedy(scorer, text, lookup, chars, is_file)
  local best
  local first = lookup:find(chars[1], 1, true)
  while first do
    scorer:start(text, first, is_file)
    local position = first
    local matched = true
    for index = 2, #chars do
      position = lookup:find(chars[index], position + 1, true)
      if not position then
        matched = false
        break
      end
      scorer:update(position)
    end
    if matched and (not best or scorer.value > best) then
      best = scorer.value
    end
    first = lookup:find(chars[1], first + 1, true)
  end
  return best
end

local MAX_DP_CELLS = 4096

local function fuzzy_match(scorer, text, lookup, chars, is_file)
  local pattern_length = #chars
  if pattern_length == 0 then
    return
  end
  if #lookup * pattern_length > MAX_DP_CELLS then
    -- ponytail: bounded DP keeps typing responsive; use the greedy matcher for
    -- unusually large inputs, and move to fzf's full V2 matrix if this ceiling matters.
    return fuzzy_match_greedy(scorer, text, lookup, chars, is_file)
  end

  local previous = {}
  local first = lookup:find(chars[1], 1, true)
  while first do
    local raw_bonus = scorer:bonus_at(text, first)
    scorer:start(text, first, is_file)
    previous[first] = { [raw_bonus] = scorer.value }
    first = lookup:find(chars[1], first + 1, true)
  end

  for index = 2, pattern_length do
    local current = {}
    local gap_best
    local character = chars[index]:byte()
    for position = 1, #lookup do
      local predecessor = previous[position - 2]
      if predecessor then
        for _, score in pairs(predecessor) do
          local value = score - (position - 3) * SCORE_GAP_EXTENSION
          if not gap_best or value > gap_best then
            gap_best = value
          end
        end
      end

      if lookup:byte(position) == character then
        local raw_bonus = scorer:bonus_at(text, position)
        local states = {}
        if gap_best then
          states[raw_bonus] = gap_best
            + SCORE_GAP_START
            + (position - 3) * SCORE_GAP_EXTENSION
            + SCORE_MATCH
            + raw_bonus
        end

        local contiguous = previous[position - 1]
        if contiguous then
          for first_bonus, score in pairs(contiguous) do
            local bonus = raw_bonus
            local next_first_bonus = first_bonus
            if bonus >= BONUS_BOUNDARY and bonus > first_bonus then
              next_first_bonus = bonus
            else
              bonus = math.max(bonus, first_bonus, BONUS_CONSECUTIVE)
            end
            local value = score + SCORE_MATCH + bonus
            if not states[next_first_bonus] or value > states[next_first_bonus] then
              states[next_first_bonus] = value
            end
          end
        end
        if next(states) then
          current[position] = states
        end
      end
    end
    previous = current
  end

  local best
  for _, states in pairs(previous) do
    for _, score in pairs(states) do
      if not best or score > best then
        best = score
      end
    end
  end
  return best
end

local function exact_match(scorer, text, lookup, term, is_file)
  local first
  local last
  if term.exact_prefix then
    if lookup:sub(1, #term.pattern) == term.pattern then
      first, last = 1, #term.pattern
    end
  elseif term.exact_suffix then
    if lookup:sub(-#term.pattern) == term.pattern then
      first, last = #lookup - #term.pattern + 1, #lookup
    end
  else
    first, last = lookup:find(term.pattern, 1, true)
    while term.word and first do
      if
        scorer:is_left_boundary(lookup, first) and scorer:is_right_boundary(lookup, last)
      then
        break
      end
      first, last = lookup:find(term.pattern, last + 1, true)
    end
  end

  if term.inverse then
    return not first and DEFAULT_SCORE or nil
  end
  if first then
    return scorer:get(text, first, last, is_file)
  end
end

local function match_term(scorer, candidate, term)
  local text = term.field == "file" and candidate.path or candidate[term.field or "text"]
  if text == nil then
    return term.inverse and DEFAULT_SCORE or nil
  end
  text = tostring(text)
  local lookup = term.ignorecase and text:lower() or text
  if term.fuzzy then
    local score = fuzzy_match(scorer, text, lookup, term.chars, candidate.path ~= nil)
    if term.inverse then
      return not score and DEFAULT_SCORE or nil
    end
    return score
  end
  return exact_match(scorer, text, lookup, term, candidate.path ~= nil)
end

local function match_candidate(scorer, candidate, groups)
  local total = 0
  for _, alternatives in ipairs(groups) do
    local score
    for _, term in ipairs(alternatives) do
      score = match_term(scorer, candidate, term)
      if score then
        break
      end
    end
    if not score then
      return nil
    end
    total = total + score
  end
  return total
end

function Ranker.new(opts)
  opts = vim.tbl_deep_extend("force", {
    filename_bonus = true,
    cwd_bonus = true,
    frecency = true,
    history_bonus = false,
  }, opts or {})
  local frecency = type(opts.frecency) == "table" and opts.frecency or nil
  if opts.frecency == true then
    frecency = require("minibuffer.fuzzy.frecency").default()
  end
  return setmetatable({
    opts = opts,
    scorer = Score.new(opts),
    cwd = opts.cwd and normalize_path(opts.cwd) or nil,
    frecency = frecency,
    bonus_cache = setmetatable({}, { __mode = "k" }),
  }, Ranker)
end

function Ranker:_bonus(candidate)
  if self.bonus_cache[candidate] ~= nil then
    return self.bonus_cache[candidate]
  end
  local bonus = 0
  if self.opts.cwd_bonus and self.cwd and candidate.path then
    local path = normalize_path(candidate.path)
    local prefix = self.cwd:sub(-1) == "/" and self.cwd or self.cwd .. "/"
    if path == self.cwd or path:sub(1, #prefix) == prefix then
      bonus = bonus + 10
    end
  end
  if self.frecency and candidate.path then
    local value = self.frecency:get(candidate)
    bonus = bonus + (1 - 1 / (1 + value)) * 8
  end
  self.bonus_cache[candidate] = bonus
  return bonus
end

function Ranker:rank(query, candidates)
  query = vim.trim(query or "")
  local groups = parse_query(self.opts, query)
  local ranked = {}

  for index, candidate in ipairs(candidates) do
    local score = #groups == 0 and DEFAULT_SCORE
      or match_candidate(self.scorer, candidate, groups)
    candidate.score = score
    if score then
      score = score + self:_bonus(candidate)
      candidate.idx = candidate.idx or index
      candidate.score = score
      ranked[#ranked + 1] = candidate
    end
  end

  table.sort(ranked, function(left, right)
    if left.score ~= right.score then
      return left.score > right.score
    end
    if #left.text ~= #right.text then
      return #left.text < #right.text
    end
    return left.idx < right.idx
  end)
  return ranked
end

local M = {}

---Create a standalone Snacks-style fuzzy ranker.
---@param opts? minibuffer.fuzzy.Opts
---@return minibuffer.fuzzy.Ranker
function M.new(opts)
  return Ranker.new(opts)
end

return M
