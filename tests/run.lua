local failures = 0
local tests = 0

function _G.test(name, fn)
  tests = tests + 1
  local ok, err = xpcall(fn, debug.traceback)
  if ok then
    io.stdout:write("ok - " .. name .. "\n")
  else
    failures = failures + 1
    io.stderr:write("not ok - " .. name .. "\n" .. err .. "\n")
  end
end

function _G.eq(expected, actual)
  if not vim.deep_equal(expected, actual) then
    error(
      ("expected: %s\nactual:   %s"):format(vim.inspect(expected), vim.inspect(actual)),
      2
    )
  end
end

function _G.near(expected, actual, epsilon)
  if math.abs(expected - actual) > (epsilon or 1e-9) then
    error(("expected %s to be near %s"):format(actual, expected), 2)
  end
end

dofile("tests/fuzzy_spec.lua")
dofile("tests/frecency_spec.lua")
dofile("tests/fzf_lua_spec.lua")
dofile("tests/cmd_spec.lua")

if failures > 0 then
  error(("%d of %d tests failed"):format(failures, tests))
end

io.stdout:write(("1..%d\n"):format(tests))
