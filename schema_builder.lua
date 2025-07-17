local plugin = require("wezterm.plugin")

return plugin.with_schema({
	name = "sessionizer",
	description = "Project-based sessionizer plugin for WezTerm",
	parameters = {
		projects = {
			description = "List of project base directories and their max depth.",
			type = "array",
			default = {},
			example = {
				{ path = "~/projects", max_depth = 3 },
				{ path = "~/work", max_depth = 2 },
			},
			items = {
				oneOf = {
					{ type = "string" },
					{
						type = "object",
						properties = {
							path = {
								description = "Path to the base directory.",
								type = "string",
							},
							max_depth = {
								description = "Maximum recursive search depth.",
								type = "integer",
								default = 3,
							},
						},
						required = { "path" },
					},
				},
			},
		},

		exclude_dirs = {
			description = "Directory names to exclude from scanning.",
			type = "array",
			items = { type = "string" },
			default = {
				".git",
				"node_modules",
				".vscode",
				".svn",
				".hg",
				".idea",
				".DS_Store",
				"__pycache__",
				"target",
				"build",
			},
		},

		default_depth = {
			description = "Default maximum depth for directory scanning.",
			type = "integer",
			default = 3,
		},

		key = {
			description = "Key to trigger the session switcher (default: 'f')",
			type = "string",
			default = "f",
		},

		mods = {
			description = "Modifier keys to trigger the switcher (default: 'LEADER')",
			type = "string",
			default = "LEADER",
		},

		add_to_launch_menu = {
			description = "Whether to append scanned workspaces to the launch menu.",
			type = "boolean",
			default = false,
		},
	},
})
