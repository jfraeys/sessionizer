local wezterm = require("wezterm")

local State = {
	project_base = {},
	exclude_dirs = {},
	default_depth = 3,
	cached_directories = nil,
	cached_checksum = nil,
	_exclude_flags = nil,
	is_windows = wezterm.target_triple:find("windows") ~= nil,
}

function State.apply_to_config(config)
	State.project_base = config.projects or {}
	State.exclude_dirs = config.exclude_dirs or {}
	State.default_depth = config.default_depth or 3
end

function State.clear_cache()
	State.cached_directories = nil
	State.cached_checksum = nil
	State._exclude_flags = nil
end

return State
