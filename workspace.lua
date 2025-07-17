local wezterm = require("wezterm")
local state = require("state")
local command_builder = require("command_builder")
local utils = require("utils")

local M = {}

--- Get a list of all project directories across configured bases.
-- Uses cached results if checksum matches to avoid rescanning.
-- @return table: list of workspace entries with fields like `id` and `label`
function M.all_dirs()
	-- Check if cached list is valid
	if state.cached_directories then
		if utils.checksum(state.cached_directories) == state.cached_checksum then
			-- Return a copy to avoid accidental external mutation
			local copy = {}
			for i, v in ipairs(state.cached_directories) do
				copy[i] = v
			end
			return copy
		end
	end

	local list = {}
	local seen = {} -- for deduplication by id

	for _, base in ipairs(state.project_base) do
		local ok, scanned = pcall(command_builder.scan_base, base)
		if ok and scanned then
			for _, folder in ipairs(scanned) do
				if not seen[folder.id] then
					table.insert(list, folder)
					seen[folder.id] = true
				end
			end
		else
			wezterm.log_error("Failed to scan project base: " .. tostring(base.path))
		end
	end

	-- Update cache and checksum
	state.cached_directories = list
	state.cached_checksum = utils.checksum(list)

	return list
end

return M
