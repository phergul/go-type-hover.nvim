local M = {}

local function scan_for_block(lines)
	local depth = 0
	local saw_open = false
	for i, line in ipairs(lines) do
		for j = 1, #line do
			local ch = line:sub(j, j)
			if ch == "{" then
				depth = depth + 1
				saw_open = true
			elseif ch == "}" and saw_open then
				depth = depth - 1
				if depth == 0 then
					return i, true
				end
			end
		end
	end
	return nil, saw_open
end

local function skip_leading_comments(lines, start_line)
	local offset = 0
	for i, line in ipairs(lines) do
		local trimmed = line:gsub("^%s+", "")
		if trimmed:match("^type%s+") then
			return start_line + (i - 1)
		end
		if
			trimmed == ""
			or trimmed:match("^//")
			or trimmed:match("^/%*")
			or trimmed:match("^%*")
			or trimmed:match("^%*/")
		then
			offset = i
		else
			break
		end
	end
	return start_line + offset
end

function M.extract(bufnr, start_line, end_line)
	local line_count = vim.api.nvim_buf_line_count(bufnr)
	local safe_start = math.max(0, start_line or 0)
	local safe_end = math.min(line_count - 1, end_line or safe_start)

	local lines = vim.api.nvim_buf_get_lines(bufnr, safe_start, line_count, false)
	if #lines == 0 then
		return { lines = {}, start_line = safe_start }
	end

	local adjusted_start = skip_leading_comments(lines, safe_start)
	if adjusted_start ~= safe_start then
		lines = vim.api.nvim_buf_get_lines(bufnr, adjusted_start, line_count, false)
		safe_start = adjusted_start
	end

	local end_index, saw_open = scan_for_block(lines)

	if end_index then
		local block = {}
		for i = 1, end_index do
			block[#block + 1] = lines[i]
		end
		return { lines = block, start_line = safe_start }
	end

	if not saw_open then
		local range_lines = vim.api.nvim_buf_get_lines(bufnr, safe_start, safe_end + 1, false)
		return { lines = range_lines, start_line = safe_start }
	end

	return { lines = lines, start_line = safe_start }
end

return M
