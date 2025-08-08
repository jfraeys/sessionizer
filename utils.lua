local wezterm = require("wezterm")
local State = require("plugins.sessionizer.state")

local M = {}

--- Retry a shell command up to `retries` times with delay between attempts.
-- @param cmd table: command and arguments
-- @param retries number: number of attempts
-- @param delay_ms number: delay in milliseconds between attempts
-- @return boolean, string|nil: success status and output
function M.retry_command(cmd, retries, delay_ms)
	for a = 1, retries do
		local ok, out = wezterm.run_child_process(cmd)
		if ok then
			return true, out
		end
		if a < retries then
			wezterm.log_error(("Retrying: %s (Attempt %d/%d)"):format(table.concat(cmd, " "), a, retries))
			wezterm.sleep_ms(delay_ms)
		end
	end
	return false
end

--- Calculate a basic checksum from a list of items (based on `id` string).
-- Used for detecting changes in project listings.
-- @param list table: list of tables with `id` field
-- @return string: 8-digit hex checksum
function M.checksum(list)
	local h = 0
	for _, v in ipairs(list) do
		for i = 1, #v.id do
			h = (h * 31 + v.id:byte(i)) & 0xFFFFFFFF
		end
	end
	return ("%08x"):format(h)
end

--- Return platform-specific exclude flags for `fd` or PowerShell.
-- Memoized to avoid rebuilding each call.
-- @return table: list of flags for file search
function M.get_exclude_flags()
	if State._exclude_flags then
		return State._exclude_flags
	end
	local flags = {}
	for _, d in ipairs(State.exclude_dirs) do
		table.insert(flags, State.is_windows and "-Exclude" or "--exclude")
		table.insert(flags, d)
	end
	State._exclude_flags = flags
	return flags
end

--- Return max-depth flags for `fd` and `find`.
-- @param req number|nil: requested depth, or fallback to default
-- @return table, table: fd-style flags, find-style flags
function M.depth_flags(req)
	if req == -1 then
		-- Unlimited depth
		return {}, {}
	end
	local d = req or State.DEFAULT_DEPTH
	return { "--max-depth", tostring(d) }, { "-maxdepth", tostring(d) }
end

--- Return the final component (basename) of a path.
-- Works on both `/` and `\` for cross-platform support.
-- @param path string: full path
-- @return string: base directory or file name
function M.basename(path)
	return path:match("([^/\\]+)[/\\]*$") or path
end

--- Build a list of prune flags for use in a `find` command.
-- These exclude specific subdirectories during traversal.
-- @param base string: base path
-- @param dirs table: list of directory names to exclude
-- @return table: list of flags for `find`
function M.build_prune_flags(base, dirs)
	local flags = {}
	for _, d in ipairs(dirs or {}) do
		table.insert(flags, "(")
		table.insert(flags, "-path")
		table.insert(flags, base .. "/" .. d)
		table.insert(flags, "-prune")
		table.insert(flags, ")")
		table.insert(flags, "-o")
	end
	return flags
end

return M
