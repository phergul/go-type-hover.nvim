local M = {}

M.stack = {}

function M.top()
	return M.stack[#M.stack]
end

function M.push(frame)
	table.insert(M.stack, frame)
end

function M.pop()
	return table.remove(M.stack)
end

function M.get_frame(win)
	for _, frame in ipairs(M.stack) do
		if frame.win == win then
			return frame
		end
	end
	return nil
end

function M.remove_by_win(win)
	for i = #M.stack, 1, -1 do
		if M.stack[i].win == win then
			table.remove(M.stack, i)
			return true
		end
	end
	return false
end

function M.close_win(win)
	if not win or not vim.api.nvim_win_is_valid(win) then
		return
	end
	M.remove_by_win(win)
	vim.api.nvim_win_close(win, true)
end

function M.close_top()
	local current = M.top()
	if not current then
		return
	end

	M.close_win(current.win)

	local prev = M.top()
	if prev and prev.win and vim.api.nvim_win_is_valid(prev.win) then
		-- explicitly set focus to the previous window
		vim.api.nvim_set_current_win(prev.win)
	end
end

function M.close_all()
	for i = #M.stack, 1, -1 do
		local frame = M.stack[i]
		if frame.win and vim.api.nvim_win_is_valid(frame.win) then
			pcall(vim.api.nvim_win_close, frame.win, true)
		end
	end
	M.stack = {}
end

return M
