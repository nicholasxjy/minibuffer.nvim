-- Compatibility alias; use `minibuffer.integrations.fzf` for new code.
local backend = package.loaded["fzf-lua"] or require("fzf-lua")
local integration = package.loaded["minibuffer.integrations.fzf"]
if integration and integration._fzf_lua ~= backend then
  package.loaded["minibuffer.integrations.fzf"] = nil
end
return require("minibuffer.integrations.fzf")
