local wezterm = require("wezterm")
local act = wezterm.action

-- WorkspaceManager to encapsulate the state
local WorkspaceManager = {
	project_base = {},
	cached_directories = nil, -- Cache for directories
}

local is_windows = string.find(wezterm.target_triple, "windows") ~= nil

--- Utility function for logging errors and returning them
---@param message string
---@return nil, string
local function log_and_return_error(message)
	wezterm.log_error(message)
	return nil, message
end

--- Utility function for retrying commands in case of failures
---@param cmd table
---@param retries number
---@param delay number
---@return string|nil, string|nil
local function retry_command(cmd, retries, delay)
	for attempt = 1, retries do
        local success, result, err = command_run_with_retry(cmd)
		if success then
			return result
		end
		wezterm.log_error(
			"Retrying command: " .. table.concat(cmd, " ") .. " (Attempt " .. attempt .. " of " .. retries .. ")"
		)
		wezterm.sleep_ms(delay)
	end
	return log_and_return_error("Command failed after " .. retries .. " attempts: " .. table.concat(cmd, " "))
end

--- Runs a shell command and handles errors, with retry support
---@param cmd table
---@param retries number
---@param delay number
---@return string|nil, string|nil
local function command_run_with_retry(cmd, retries, delay)
	local stdout, stderr, success

	if not cmd then
		return log_and_return_error("No command provided to run")
	end

	if is_windows then
		local is_wsl = os.getenv("WSL_DISTRO_NAME") ~= nil
		if is_wsl then
			success, stdout, stderr = wezterm.run_child_process({ "wsl", table.unpack(cmd) })
		else
			success, stdout, stderr = wezterm.run_child_process({ "powershell", "-command", table.unpack(cmd) })
		end
	else
		success, stdout, stderr = wezterm.run_child_process({ os.getenv("SHELL"), "-c", table.concat(cmd, " ") })
	end

	if not success then
		wezterm.log_error("Initial command failed: " .. (stderr or "Unknown error"))
		return retry_command(cmd, retries, delay)
	end

	return stdout
end

--- Fetch directories for workspace, leveraging caching and retrying
---@return table|nil
local function get_directories()
	if WorkspaceManager.cached_directories then
		return WorkspaceManager.cached_directories -- Return cached data if available
	end

	local folders = {}

	for _, base_path in ipairs(WorkspaceManager.project_base) do
		local command = nil
		if is_windows then
			command = { "Get-ChildItem", "-Path", base_path, "-Directory" }
		else
			local fd_check_cmd = { "sh", "-c", "command -v fd" }
			local fd_check = command_run_with_retry(fd_check_cmd, 3, 500) -- Retry fd check up to 3 times
			if fd_check then
				command = { "fd", ".", "-H", "--min-depth", "1", "--max-depth", "3", "-t", "d", base_path }
			else
				command = { "find", base_path, "-mindepth", "1", "-maxdepth", "3", "-type", "d" }
			end
		end

		local out = command_run_with_retry(command, 3, 500) -- Retry the directory fetching command 3 times
		if not out then
			return log_and_return_error("Error fetching directories after retries")
		end

		for _, path in ipairs(wezterm.split_by_newlines(out)) do
			local updated_path = path:gsub(wezterm.home_dir, "~")
			table.insert(folders, { id = path, label = updated_path })
		end
	end

	WorkspaceManager.cached_directories = folders -- Cache the results after first run
	return folders
end

--- Logic to switch between workspaces based on user selection
---@param window any
---@param pane any
---@param id string|nil
---@param label string|nil
local function switch_workspace_logic(window, pane, id, label)
	if not id or not label then
		-- This is reached when the user exits or no result is found
		wezterm.log_info("User exited the selection or no workspace selected.")
		return
	end

	local full_path = label:gsub("^~", wezterm.home_dir)

	local action_data = nil
	if full_path:sub(1, 1) == "/" or full_path:sub(2, 2) == ":" then
		action_data = {
			name = label,
			spawn = {
				label = "Workspace: " .. label,
				cwd = full_path,
			},
		}
	else
		action_data = { name = id }
	end

	window:perform_action(act.SwitchToWorkspace(action_data), pane)
end

--- Workspace switcher logic that fetches directories lazily
---@return function
local function workspace_switcher()
	return wezterm.action_callback(function(window, pane)
		-- Get directories before calling the coroutine-based action
		local workspaces = get_directories()
		if not workspaces or #workspaces == 0 or workspaces == nil then
			wezterm.log_info("No workspaces found to select.")
			return
		end

		-- Show the input selector to choose workspaces
		window:perform_action(
			act.InputSelector({
				action = wezterm.action_callback(function(inner_window, inner_pane, id, label)
					if not id and not label then
						-- If no selection made, handle user exit
						wezterm.log_info("User exited the selection.")
					else
						-- Handle valid workspace selection
						switch_workspace_logic(inner_window, inner_pane, id, label)
					end
				end),
				title = "Wezterm Sessionizer",
				choices = workspaces,
				fuzzy = true,
			}),
			pane
		)
	end)
end

--- Set up key bindings for Wezterm
---@param config table
local function configure(config)
	table.insert(config.keys, {
		key = "f",
		mods = "LEADER",
		action = workspace_switcher(), -- Trigger lazy directory fetching
	})
end

--- Set project paths to be used for workspace switching
---@param paths table
local function set_projects(paths)
	WorkspaceManager.project_base = paths
	WorkspaceManager.cached_directories = nil -- Reset cache when new paths are set
end

--- Module return structure
return {
	configure = configure,
	set_projects = set_projects,
	switch_workspace = workspace_switcher,
}
