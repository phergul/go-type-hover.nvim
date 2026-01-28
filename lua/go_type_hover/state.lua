local M = {}

M.stack = {}

---Returns the top frame of the stack
---@return table|nil The top frame or nil if empty
function M.top()
	return M.stack[#M.stack]
end

---Pushes a new frame onto the stack
---@param frame table The frame to push (win, buf, etc.)
function M.push(frame)
	table.insert(M.stack, frame)
end

---Pops the top frame from the stack
---@return table|nil The popped frame or nil if empty
function M.pop()
	return table.remove(M.stack)
end

---Retrieves the frame associated with the given window handle
---@param win number The window handle
---@return table|nil The found frame or nil
function M.get_frame(win)
	for _, frame in ipairs(M.stack) do
		if frame.win == win then
			return frame
		end
	end
	return nil
end

---Removes a frame from the stack by its window handle
---@param win number The window handle
---@return boolean True if removed, false otherwise
function M.remove_by_win(win)
	for i = #M.stack, 1, -1 do
		if M.stack[i].win == win then
			table.remove(M.stack, i)
			return true
		end
	end
	return false
end

---Closes the specified window and removes its frame from the stack
---@param win number The window handle
function M.close_win(win)
	if not win or not vim.api.nvim_win_is_valid(win) then
		return
	end
	M.remove_by_win(win)
	vim.api.nvim_win_close(win, true)
end

---Closes the top floating window and focuses the previous one if available
function M.close_top()
	local current = M.top()
	if not current then
		return
	end

	M.close_win(current.win)

	local prev = M.top()
	if prev and prev.win and vim.api.nvim_win_is_valid(prev.win) then
		vim.api.nvim_set_current_win(prev.win)
		-- Restore title and footer for the active window
		if prev.title or prev.footer then
			vim.api.nvim_win_set_config(prev.win, {
				title = prev.title or "",
				title_pos = prev.title and "center" or nil,
				footer = prev.footer or "",
				footer_pos = prev.footer and "center" or nil,
			})
		end
	end
end

---Closes all floating windows managed by the plugin and clears the stack
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
