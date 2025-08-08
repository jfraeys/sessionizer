local wezterm = require("wezterm")
local state = require("plugins.sessionizer.state")
local ui = require("plugins.sessionizer.ui")
local workspaces = require("plugins.sessionizer.workspaces")

local M = {}

function M.apply_to_config(config, user_config)
	local opts = user_config or {}

	-- Let State handle config applying and defaults
	state.apply_to_config(opts)

	-- Normalize projects for internal use
	state.project_base = {}
	for _, base in ipairs(opts.projects or {}) do
		table.insert(state.project_base, {
			path = base.path or base,
			max_depth = base.max_depth or state.default_depth,
		})
	end

	-- Setup keybinding
	table.insert(config.keys, {
		key = opts.key,
		mods = opts.mods,
		action = ui.make_switcher(),
	})

	-- Add launch menu if requested
	if opts.add_to_launch_menu then
		config.launch_menu = config.launch_menu or {}
		for _, dir in ipairs(workspaces.all_dirs()) do
			table.insert(config.launch_menu, {
				label = "Workspace: " .. wezterm.basename(dir),
				cwd = dir,
				args = { "nvim" },
			})
		end
	end
end

return M
