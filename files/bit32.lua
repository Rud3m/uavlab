-- bit32.lua compatibility layer for Lua 5.3+
-- This file provides a 'bit32' module that maps to the native bitwise operators.

local M = {}

local function checkinteger(v, argpos)
    if type(v) ~= "number" then
        error("bad argument #" .. (argpos or 1) .. " (number expected, got " .. type(v) .. ")", 3)
    end
    return math.floor(v) -- Ensure it's an integer for bitwise ops
end

function M.band(...)
    local res = -1 -- All bits set
    for i, v in ipairs({...}) do
        res = res & checkinteger(v, i)
    end
    return res
end

function M.bnot(x)
    return ~checkinteger(x, 1)
end

function M.bor(...)
    local res = 0
    for i, v in ipairs({...}) do
        res = res | checkinteger(v, i)
    end
    return res
end

function M.bxor(...)
    local res = 0
    for i, v in ipairs({...}) do
        res = res ~ checkinteger(v, i) -- Lua 5.4 uses `~` for XOR
    end
    return res
end

function M.lshift(x, n)
    return checkinteger(x, 1) << checkinteger(n, 2)
end

function M.rshift(x, n)
    return checkinteger(x, 1) >> checkinteger(n, 2)
end

function M.arshift(x, n)
    -- Arithmetic right shift (preserves sign bit) is generally the same as logical right shift
    -- for positive numbers in Lua's native implementation.
    -- For negative numbers, Lua 5.4's >> performs an arithmetic shift.
    return checkinteger(x, 1) >> checkinteger(n, 2)
end

-- Note: rol and ror (rotate left/right) are not natively supported as operators
-- and require more complex implementation if the original script uses them for 32-bit values.
-- For most MAVLink parsing, band, bor, lshift, rshift are sufficient.
-- If your plugin requires `rol` or `ror`, this shim might need further adjustments.

function M.btest(...)
    -- btest(a, b) returns true if (a & b) ~= 0
    return M.band(...) ~= 0
end

function M.extract(n, field, width)
    width = width or 1
    local val = checkinteger(n, 1)
    local f = checkinteger(field, 2)
    local w = checkinteger(width, 3)
    return (val >> f) & ((1 << w) - 1)
end

function M.replace(n, v, field, width)
    width = width or 1
    local val = checkinteger(n, 1)
    local new_val = checkinteger(v, 2)
    local f = checkinteger(field, 3)
    local w = checkinteger(width, 4)
    local mask = ((1 << w) - 1) << f
    return (val & (~mask)) | ((new_val << f) & mask)
end

return M