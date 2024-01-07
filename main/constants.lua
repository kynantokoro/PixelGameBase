local M = {}

-- put all global constants here
local _private = {
	GAME_WIDTH = 320,
	GAME_HEIGHT = 240
}

-- Metatable to prevent external modification
local mt = {
	__index = function(table, key)
		return _private[key]
	end,

	__newindex = function(table, key, value)
		error("Attempt to modify read-only table")
	end
}

setmetatable(M, mt)

return M