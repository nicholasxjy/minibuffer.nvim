-- Scoring criteria and constants follow fzf's fuzzy matcher.
-- Copyright (c) 2013-2026 Junegunn Choi, distributed under the MIT license.
-- https://github.com/junegunn/fzf/blob/master/LICENSE

local SCORE_MATCH = 16
local SCORE_GAP_START = -3
local SCORE_GAP_EXTENSION = -1

local BONUS_BOUNDARY = SCORE_MATCH / 2
local BONUS_NONWORD = SCORE_MATCH / 2
local BONUS_CAMEL_123 = BONUS_BOUNDARY - 1
local BONUS_CONSECUTIVE = -(SCORE_GAP_START + SCORE_GAP_EXTENSION)
local BONUS_FIRST_CHAR_MULTIPLIER = 2
local BONUS_NO_PATH_SEP = BONUS_BOUNDARY - 2

local CHAR_WHITE = 0
local CHAR_NONWORD = 1
local CHAR_DELIMITER = 2
local CHAR_LOWER = 3
local CHAR_UPPER = 4
local CHAR_LETTER = 5
local CHAR_NUMBER = 6

local CHAR_CLASS = {}
for byte = 0, 255 do
  local char = string.char(byte)
  if char:match("%s") then
    CHAR_CLASS[byte] = CHAR_WHITE
  elseif char:match("[/\\,:;|]") then
    CHAR_CLASS[byte] = CHAR_DELIMITER
  elseif byte >= 48 and byte <= 57 then
    CHAR_CLASS[byte] = CHAR_NUMBER
  elseif byte >= 65 and byte <= 90 then
    CHAR_CLASS[byte] = CHAR_UPPER
  elseif byte >= 97 and byte <= 122 then
    CHAR_CLASS[byte] = CHAR_LOWER
  else
    CHAR_CLASS[byte] = CHAR_NONWORD
  end
end

local Score = {}
Score.__index = Score

local function compute_bonus(self, previous, current)
  if current > CHAR_NONWORD then
    if previous == CHAR_WHITE then
      return self.boundary_white
    elseif previous == CHAR_DELIMITER then
      return self.boundary_delimiter
    elseif previous == CHAR_NONWORD then
      return BONUS_BOUNDARY
    end
  end

  if
    (previous == CHAR_LOWER and current == CHAR_UPPER)
    or (previous ~= CHAR_NUMBER and current == CHAR_NUMBER)
  then
    return BONUS_CAMEL_123
  end
  if current == CHAR_NONWORD or current == CHAR_DELIMITER then
    return BONUS_NONWORD
  elseif current == CHAR_WHITE then
    return BONUS_BOUNDARY + 2
  end
  return 0
end

function Score.new(opts)
  local self = setmetatable({}, Score)
  self.opts = opts or {}
  self.path_separator = self.opts.path_separator or package.config:sub(1, 1)
  self.boundary_white = self.opts.history_bonus and BONUS_BOUNDARY or BONUS_BOUNDARY + 2
  self.boundary_delimiter = self.opts.history_bonus and BONUS_BOUNDARY
    or BONUS_BOUNDARY + 1
  self.bonuses = {}
  for previous = 0, 6 do
    self.bonuses[previous] = {}
    for current = 0, 6 do
      self.bonuses[previous][current] = compute_bonus(self, previous, current)
    end
  end
  return self
end

function Score:start(text, first, is_file)
  self.text = text
  self.value = 0
  self.consecutive = 0
  self.previous = nil
  self.previous_class = first > 1 and (CHAR_CLASS[text:byte(first - 1)] or CHAR_NONWORD)
    or CHAR_WHITE
  self.first_bonus = 0

  if
    is_file
    and self.opts.filename_bonus ~= false
    and not text:find(self.path_separator, first + 1, true)
    and not (self.path_separator ~= "/" and text:find("/", first + 1, true))
  then
    self.value = self.value + BONUS_NO_PATH_SEP
  end
  self:update(first)
end

function Score:update(position)
  local class = CHAR_CLASS[self.text:byte(position)] or CHAR_NONWORD
  local gap = self.previous and position - self.previous - 1 or 0
  local bonus

  if gap > 0 then
    self.previous_class = CHAR_CLASS[self.text:byte(position - 1)] or CHAR_NONWORD
    bonus = self.bonuses[self.previous_class][class]
    self.value = self.value + SCORE_GAP_START + (gap - 1) * SCORE_GAP_EXTENSION
    self.consecutive = 0
    self.first_bonus = 0
  else
    bonus = self.bonuses[self.previous_class][class]
    if self.consecutive == 0 then
      self.first_bonus = bonus
    else
      if bonus >= BONUS_BOUNDARY and bonus > self.first_bonus then
        self.first_bonus = bonus
      end
      bonus = math.max(bonus, self.first_bonus, BONUS_CONSECUTIVE)
    end
    self.consecutive = self.consecutive + 1
  end

  if not self.previous then
    bonus = bonus * BONUS_FIRST_CHAR_MULTIPLIER
  end
  self.value = self.value + SCORE_MATCH + bonus
  self.previous_class = class
  self.previous = position
end

function Score:get(text, first, last, is_file)
  self:start(text, first, is_file)
  for position = first + 1, last do
    self:update(position)
  end
  return self.value
end

function Score:is_left_boundary(text, position)
  return position == 1
    or (CHAR_CLASS[text:byte(position - 1)] or CHAR_NONWORD) < CHAR_LOWER
end

function Score:is_right_boundary(text, position)
  return position == #text
    or (CHAR_CLASS[text:byte(position + 1)] or CHAR_NONWORD) < CHAR_LOWER
end

return Score
