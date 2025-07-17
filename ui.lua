local wezterm = require("wezterm")
local act = wezterm.action
local workspace = require("workspaces")

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

	-- Expand ~ to home directory reliably
	local cwd = wezterm.expand_path(id)

	win:perform_action(
		act.SwitchToWorkspace({
			name = id, -- use the full path or unique ID as workspace name
			spawn = {
				label = "Workspace: " .. label,
				cwd = cwd,
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
			-- Notify user visually that no workspaces are available
			wezterm.toast_notification({
				title = "Sessionizer",
				message = "No workspaces found",
				timeout_milliseconds = 3000,
			})
			return
		end

		win:perform_action(
			act.InputSelector({
				title = "WezTerm Sessionizer",
				fuzzy = true, -- Enable fuzzy search
				-- Case-insensitive search (default is true, but explicit is nice)
				fuzzy_match_algorithm = "fzy",
				choices = choices,
				action = wezterm.action_callback(switch_logic),
			}),
			pane
		)
	end)
end

return M
