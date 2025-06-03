local wezterm = require("wezterm")
local act = wezterm.action

local home = os.getenv("HOME")

local WorkspaceManager = {
	project_base = {},
	exclude_dirs = { ".git", ".svn", ".hg", ".idea", ".vscode", ".DS_Store", "__pycache__" },
	cached_directories = nil,
	cached_checksum = nil,
	aliases = {
		[home .. "/Library/CloudStorage/GoogleDrive-jfraeys@gmail.com/My Drive"] = "GDrive",
		[home .. "/Documents/dev"] = "dev",
	},
}

-- Retry a shell command with delay
local function retry_command(cmd, retries, delay_ms)
	for attempt = 1, retries do
		local success, stdout = wezterm.run_child_process(cmd)
		if success then
			return true, stdout
		elseif attempt < retries then
			wezterm.log_error(
				"Retrying command: " .. table.concat(cmd, " ") .. " (Attempt " .. attempt .. " of " .. retries .. ")"
			)
			wezterm.sleep_ms(delay_ms)
		end
	end
	return false, nil
end

-- Calculate simple checksum for caching directories
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

-- Build exclude flags for commands dynamically
local function build_exclude_flags()
	local flags = {}
	for _, dir in ipairs(WorkspaceManager.exclude_dirs) do
		table.insert(flags, "--exclude")
		table.insert(flags, dir)
	end
	return flags
end

-- Build directory listing command based on platform and availability of fd
local function build_directory_command(base_path)
	local exclude_flags = build_exclude_flags()
	-- Check if fd is available
	local has_fd, _ = wezterm.run_child_process({ "command", "-v", "fd" })
	if has_fd then
		local cmd = {
			"fd",
			".",
			base_path,
			"--type",
			"d",
			"--min-depth",
			"1",
			"--max-depth",
			"3",
		}
		for _, flag in ipairs(exclude_flags) do
			table.insert(cmd, flag)
		end
		return cmd
	else
		-- fallback to find
		local cmd = { "find", base_path, "-mindepth", "1", "-maxdepth", "3", "-type", "d" }
		if #WorkspaceManager.exclude_dirs > 0 then
			table.insert(cmd, "(")
			for i, dir in ipairs(WorkspaceManager.exclude_dirs) do
				if i > 1 then
					table.insert(cmd, "-o")
				end
				table.insert(cmd, "-path")
				table.insert(cmd, "*/" .. dir)
			end
			table.insert(cmd, ")")
			table.insert(cmd, "-prune")
			table.insert(cmd, "-o")
		end
		table.insert(cmd, "-print")
		return cmd
	end
end

-- Fetch directories from a base path with retries
local function fetch_directories_from_base(base_path)
	local cmd = build_directory_command(base_path)
	local success, out = retry_command(cmd, 3, 200)
	if not success then
		wezterm.log_error("Error fetching directories after retries for base path: " .. base_path)
		return {}
	end

	local folders = {}
	for _, path in ipairs(wezterm.split_by_newlines(out)) do
		local label = path:gsub(home, "~")
		table.insert(folders, { id = path, label = label })
	end
	return folders
end

-- Main directory fetching with caching
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

-- Logic for switching workspace or opening file
local function switch_workspace_logic(window, pane, id, label)
	if not id or not label then
		wezterm.log_info("User exited the selection or no workspace selected.")
		return
	end

	local full_path = label:gsub("^~", home)

	-- Shorten path using aliases
	local function get_short_name(path)
		for root, alias in pairs(WorkspaceManager.aliases) do
			if path:find(root, 1, true) == 1 then
				local relative = path:sub(#root + 2) -- skip slash
				if relative ~= "" then
					return alias .. "/" .. relative
				else
					return alias
				end
			end
		end
		return path:match("([^/]+)/*$") or path
	end

	local function is_file(path)
		-- `test -f` returns exit code 0 if file exists
		return wezterm.run_child_process({ "test", "-f", path })
	end

	-- Get real path using realpath command (fallback to input path)
	local function get_real_path(path)
		local success, output = wezterm.run_child_process({ "realpath", path })
		if success then
			return wezterm.split_by_newlines(output)[1] or path
		end
		return path
	end

	-- Check if workspace exists
	local function workspace_exists(name)
		for _, ws in ipairs(wezterm.mux.get_workspace_names()) do
			if ws == name then
				return true
			end
		end
		return false
	end

	if is_file(full_path) then
		local real_path = get_real_path(full_path)
		local file_dir = real_path:match("(.*/)")
		if file_dir then
			file_dir = file_dir:gsub("/$", "") -- remove trailing slash
		else
			file_dir = home
		end

		local file_name = real_path:match(".+/([^/]+)$") or ""
		local short_name = get_short_name(file_dir)

		if workspace_exists(short_name) then
			window:perform_action(act.SwitchToWorkspace({ name = short_name }), pane)
		else
			window:perform_action(
				act.SwitchToWorkspace({
					name = short_name,
					spawn = { label = "Workspace: " .. short_name, cwd = file_dir },
				}),
				pane
			)
		end

		-- Open file in new tab inside current workspace
		if file_name then
			window:perform_action(
				act.SpawnCommandInNewTab({
					label = "nvim " .. file_name,
					cwd = file_dir,
					args = { "nvim", file_name },
				}),
				pane
			)
		end
	else
		local real_path = get_real_path(full_path)
		local short_name = get_short_name(real_path)

		if workspace_exists(short_name) then
			window:perform_action(act.SwitchToWorkspace({ name = short_name }), pane)
		else
			window:perform_action(
				act.SwitchToWorkspace({
					name = short_name,
					spawn = { label = "Workspace: " .. short_name, cwd = real_path },
				}),
				pane
			)
		end
	end
end

-- Returns the wezterm action callback for workspace switching UI
local function workspace_switcher()
	return wezterm.action_callback(function(window, pane)
		local workspaces = get_directories()
		if not workspaces or #workspaces == 0 then
			wezterm.log_info("No workspaces found to select.")
			return
		end

		window:perform_action(
			act.InputSelector({
				title = "Wezterm Sessionizer",
				choices = workspaces,
				fuzzy = true,
				action = wezterm.action_callback(function(inner_window, inner_pane, id, label)
					switch_workspace_logic(inner_window, inner_pane, id, label)
				end),
			}),
			pane
		)
	end)
end

-- Public configure function to bind keys
local function configure(config)
	table.insert(config.keys, {
		key = "f",
		mods = "LEADER",
		action = workspace_switcher(),
	})
end

-- Public function to set project base paths and clear cache
local function set_projects(paths)
	WorkspaceManager.project_base = paths
	WorkspaceManager.cached_directories = nil
	WorkspaceManager.cached_checksum = nil
end

return {
	configure = configure,
	set_projects = set_projects,
	switch_workspace = workspace_switcher,
}
