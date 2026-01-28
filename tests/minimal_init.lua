local function get_plugin_dir(name, env_var)
	if os.getenv(env_var) then
		return os.getenv(env_var)
	end
	local lazy_path = vim.fn.stdpath("data") .. "/lazy/" .. name
	if vim.fn.isdirectory(lazy_path) == 1 then
		return lazy_path
	end
	return nil
end

local plenary_dir = get_plugin_dir("plenary.nvim", "PLENARY_DIR")
local ts_dir = get_plugin_dir("nvim-treesitter", "TS_DIR")

if not plenary_dir then
	error("plenary.nvim not found. Please set PLENARY_DIR or install it in " .. vim.fn.stdpath("data") .. "/lazy/")
end

if not ts_dir then
	error("nvim-treesitter not found. Please set TS_DIR or install it in " .. vim.fn.stdpath("data") .. "/lazy/")
end

vim.opt.rtp:append(plenary_dir)
vim.opt.rtp:append(ts_dir)
vim.opt.rtp:append(".")

vim.cmd("runtime! plugin/plenary.vim")
