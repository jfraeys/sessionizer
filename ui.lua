local wezterm = require("wezterm")
local act = wezterm.action
local command_builder = require("plugins.sessionizer.command_builder")
local workspace = require("plugins.sessionizer.workspaces")

local M = {}

-- Callback function that handles switching to a workspace
-- @param win: wezterm window object
-- @param pane: wezterm pane object
-- @param id: workspace id (usually the full path)
-- @param label: display label (usually basename or shortened path)
local function switch_logic(win, pane, id, label)
	if not id or id == "" then
		wezterm.log_warn("No workspace ID provided for switch")
		return
	end

	local metadata = command_builder.meta_lookup[id] or {}

	-- Determine workspace name: use metadata.workspace or fallback to basename of id
	local workspace_name = metadata.workspace or wezterm.basename(id)
	local title_label = metadata.title or ("Workspace: " .. label)

	win:perform_action(
		act.SwitchToWorkspace({
			name = workspace_name, -- Use workspace name from metadata or fallback
			spawn = {
				label = title_label, -- Title shown on tab or workspace label
				cwd = id, -- Start cwd for workspace
			},
		}),
		pane
	)
end

--- Creates a wezterm InputSelector action for choosing and switching workspace.
-- Returns a function suitable for keybinding or callback.
function M.make_switcher()
	return wezterm.action_callback(function(win, pane)
		local choices = workspace.all_dirs()

		if #choices == 0 then
			wezterm.toast_notification({
				title = "Sessionizer",
				message = "No projects found",
				timeout_milliseconds = 2000,
			})
			return
		end

		win:perform_action(
			act.InputSelector({
				title = "Sessionizer",
				fuzzy = true,
				fuzzy_description = "Fuzzy search projects: ",
				choices = choices,
				action = wezterm.action_callback(switch_logic),
			}),
			pane
		)
	end)
end

return M
