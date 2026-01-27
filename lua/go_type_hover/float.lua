local state = require("go_type_hover.state")

local M = {}

local function map(buf, lhs, rhs)
	vim.keymap.set("n", lhs, rhs, { buffer = buf, nowait = true, silent = true })
end

function M.open(lines, opts, actions)
	local buf = vim.api.nvim_create_buf(false, true)

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	local win_opts = {
		relative = opts.relative,
		row = opts.row,
		col = opts.col,
		width = opts.width,
		height = opts.height,
		border = opts.border or "rounded",
		style = "minimal",
		focusable = opts.focusable ~= false,
		zindex = 50,
	}

	local win = vim.api.nvim_open_win(buf, true, win_opts)

	vim.bo[buf].filetype = "go"
	vim.bo[buf].modifiable = false
	vim.bo[buf].bufhidden = "wipe"

	if actions then
		map(buf, "l", actions.enter)
		map(buf, "<CR>", actions.enter)
		map(buf, "h", actions.back)
		map(buf, "q", actions.close_all)
		map(buf, "<Esc>", actions.close_all)
	end

	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(win),
		once = true,
		callback = function()
			state.remove_by_win(win)
		end,
	})

	return buf, win
end

return M
