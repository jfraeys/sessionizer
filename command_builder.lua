local wezterm = require("wezterm")
local State = require("plugins.sessionizer.state")
local utils = require("plugins.sessionizer.utils")

local M = {}

-- Cache tool availability and scan results
local _has_fd = nil
local _scan_cache = {}
local _meta_lookup = {}

-- Check for `fd` binary without spawning full shell
local function has_fd()
	if _has_fd == nil then
		_has_fd = os.execute("command -v fd > /dev/null 2>&1") == true
	end
	return _has_fd
end

-- Build the command to scan directories
function M.build_cmd(base)
	local path, depth = base.path, base.max_depth
	local fd_d, find_d = utils.depth_flags(depth)
	local excl = utils.get_exclude_flags() or {}

	if State.is_windows then
		return { "Get-ChildItem", "-Path", path, "-Directory", table.unpack(excl) }
	end

	if has_fd() then
		return {
			"fd",
			"--min-depth",
			"1",
			table.unpack(fd_d),
			"-t",
			"d",
			path,
			table.unpack(excl),
		}
	end

	-- Build find command with exclude pruning
	local cmd = { "find", path, "-mindepth", "1", table.unpack(find_d) }
	local prune_flags = utils.build_prune_flags(path, State.exclude_dirs)
	for _, flag in ipairs(prune_flags) do
		table.insert(cmd, flag)
	end
	table.insert(cmd, "-type")
	table.insert(cmd, "d")
	table.insert(cmd, "-print")

	return cmd
end

function M.scan_base(base)
	local key = base.path .. ":" .. (base.max_depth or "default")
	if _scan_cache[key] then
		return _scan_cache[key]
	end

	local ok, out = utils.retry_command(M.build_cmd(base), 3, 200)
	if not ok then
		wezterm.log_error("Failed to scan: " .. base.path)
		return {}
	end

	local choices = {}

	for _, line in ipairs(wezterm.split_by_newlines(out)) do
		local id = line
		local label = line:gsub(wezterm.home_dir, "~")

		table.insert(choices, {
			id = id,
			label = label,
		})

		-- store metadata separately
		_meta_lookup[id] = {
			workspace = utils.basename(line),
			title = utils.basename(line),
			path = line,
		}
	end

	_scan_cache[key] = choices
	return choices
end

-- Export metadata so other modules (like ui.lua) can use it
M.meta_lookup = _meta_lookup

return M
