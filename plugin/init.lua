local wezterm = require("wezterm")
local act = wezterm.action

-- WorkspaceManager to encapsulate the state
local WorkspaceManager = {
	project_base = {},
	exclude_dirs = { ".git", ".svn", ".hg", ".idea", ".vscode", ".DS_Store", "__pycache__" },
	cached_directories = {},
	cached_checksum = nil,
}

local is_windows = string.find(wezterm.target_triple, "windows") ~= nil

--- Retry a command in case of failures
---@param cmd table
---@param retries number
---@param delay number
---@return boolean, string|nil
local function retry_command(cmd, retries, delay)
	for attempt = 1, retries do
		local success, stdout = wezterm.run_child_process(cmd)
		if success then
			return true, stdout
		elseif attempt < retries then
			wezterm.log_error(
				"Retrying command: " .. table.concat(cmd, " ") .. " (Attempt " .. attempt .. " of " .. retries .. ")"
			)
			wezterm.sleep_ms(delay)
		end
	end
	return false, nil
end

--- Calculates a checksum for directory paths to enable caching
---@param directories table
---@return string
local function calculate_checksum(directories)
	local hash = 0
	for _, dir in ipairs(directories) do
		local id = dir.id
		for i = 1, #id do
			hash = (hash * 31 + id:byte(i)) % 0xFFFFFFFF
		end
	end
	return string.format("%08x", hash)
end

--- Construct exclusion flags dynamically based on platform
local exclude_flags = {}
for _, dir in ipairs(WorkspaceManager.exclude_dirs) do
	table.insert(exclude_flags, is_windows and "-Exclude" or "--exclude")
	table.insert(exclude_flags, dir)
end

--- Build the directory fetching command based on platform and available tools
---@param base_path string
---@return table cmd
local function build_directory_command(base_path)
	if is_windows then
		-- On Windows, Get-ChildItem with -Directory flag ensures only directories (hidden or not) are listed
		return { "Get-ChildItem", "-Path", base_path, "-Directory", table.unpack(exclude_flags) }
	else
		local fd_check = wezterm.run_child_process({ "command", "-v", "fd" })
		if fd_check then
			-- Use 'fd' for finding directories (hidden or not), no need for excluding hidden dirs manually
			return {
				"fd",
				"--min-depth",
				"1",
				"--max-depth",
				"3",
				"-t",
				"d", -- Only directories (hidden or not)
				base_path,
				table.unpack(exclude_flags),
			}
		else
			-- Fallback to 'find' for directories, no need for manual exclusion of hidden files
			local cmd = { "find", base_path, "-mindepth", "1", "-maxdepth", "3", "-type", "d" } -- Only directories
			for _, dir in ipairs(WorkspaceManager.exclude_dirs) do
				table.insert(cmd, "(") -- Start group for each exclusion
				table.insert(cmd, "-path")
				table.insert(cmd, base_path .. "/" .. dir)
				table.insert(cmd, "-prune")
				table.insert(cmd, ")")
				table.insert(cmd, "-o")
			end
			table.insert(cmd, "-print") -- Only one -print at the end
			return cmd
		end
	end
end

--- Fetch directories from a given base path with retry handling
---@param base_path string
---@return table directories
local function fetch_directories_from_base(base_path)
	local cmd = build_directory_command(base_path)
	local success, out = retry_command(cmd, 3, 200)
	if not success then
		wezterm.log_error("Error fetching directories after retries for base path: " .. base_path)
		return {}
	end

	local folders = {}
	for _, path in ipairs(wezterm.split_by_newlines(out)) do
		local updated_path = path:gsub(wezterm.home_dir, "~")
		table.insert(folders, { id = path, label = updated_path })
	end
	return folders
end

--- Main function to fetch directories for workspace, leveraging caching and retrying
---@return table directories
local function get_directories()
	if WorkspaceManager.cached_directories then
		local current_checksum = calculate_checksum(WorkspaceManager.cached_directories)
		if current_checksum == WorkspaceManager.cached_checksum then
			return WorkspaceManager.cached_directories
		end
	end

	local folders = {}
	for _, base_path in ipairs(WorkspaceManager.project_base) do
		local base_folders = fetch_directories_from_base(base_path)
		for _, folder in ipairs(base_folders) do
			table.insert(folders, folder)
		end
	end

	WorkspaceManager.cached_directories = folders
	WorkspaceManager.cached_checksum = calculate_checksum(folders)
	return folders
end

--- Logic to switch between workspaces based on user selection
---@param window any
---@param pane any
---@param id string|nil
---@param label string|nil
local function switch_workspace_logic(window, pane, id, label)
	if not id or not label then
		wezterm.log_info("User exited the selection or no workspace selected.")
		return
	end

	local full_path = label:gsub("^~", wezterm.home_dir)
	local action_data = {
		name = label,
		spawn = {
			label = "Workspace: " .. label,
			cwd = full_path,
		},
	}

	window:perform_action(act.SwitchToWorkspace(action_data), pane)
end

--- Workspace switcher logic that fetches directories lazily
---@return function
local function workspace_switcher()
	return wezterm.action_callback(function(window, pane)
		local workspaces = get_directories()
		if not workspaces or #workspaces == 0 then
			wezterm.log_info("No workspaces found to select.")
			return
		end

		window:perform_action(
			act.InputSelector({
				action = wezterm.action_callback(function(inner_window, inner_pane, id, label)
					switch_workspace_logic(inner_window, inner_pane, id, label)
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
		action = workspace_switcher(),
	})
end

--- Set project paths to be used for workspace switching
---@param paths table
local function set_projects(paths)
	WorkspaceManager.project_base = paths
	WorkspaceManager.cached_directories = nil
	WorkspaceManager.cached_checksum = nil
end

--- Module return structure
return {
	configure = configure,
	set_projects = set_projects,
	switch_workspace = workspace_switcher,
}
