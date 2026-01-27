local extractor = require("go_type_hover.extractor")
local float = require("go_type_hover.float")
local resolver = require("go_type_hover.resolver")
local state = require("go_type_hover.state")

local M = {}

local default_config = {
	-- keymap to trigger type hover; set to "" to disable
	keymap = "gK",

	-- anchor position for the floating window ('cursor' or 'editor')
	anchor = "cursor",

	-- floating window options
	float = {
		-- border style for the floating window
		border = "rounded",
		-- whether the floating window can be focused
		focusable = true,
		-- maximum width of the floating window
		max_width = 80,
		-- maximum height of the floating window
		max_height = nil,
	},

	-- offset from the anchor position
	offset = { row = 1, col = 2 },

	-- identifiers to ignore
	ignored = {},
}

local config = vim.deepcopy(default_config)
local active_keymap

local ignore_list = {
	["any"] = true,
	["bool"] = true,
	["byte"] = true,
	["complex64"] = true,
	["complex128"] = true,
	["error"] = true,
	["float32"] = true,
	["float64"] = true,
	["int"] = true,
	["int8"] = true,
	["int16"] = true,
	["int32"] = true,
	["int64"] = true,
	["rune"] = true,
	["string"] = true,
	["uint"] = true,
	["uint8"] = true,
	["uint16"] = true,
	["uint32"] = true,
	["uint64"] = true,
	["uintptr"] = true,
	["map"] = true,
	["chan"] = true,
	["struct"] = true,
	["interface"] = true,
	["func"] = true,
	["var"] = true,
	["const"] = true,
	["type"] = true,
	["package"] = true,
	["import"] = true,
	["return"] = true,
	["defer"] = true,
	["go"] = true,
	["select"] = true,
	["case"] = true,
	["default"] = true,
	["switch"] = true,
	["if"] = true,
	["else"] = true,
	["for"] = true,
	["range"] = true,
	["break"] = true,
	["continue"] = true,
	["goto"] = true,
}

local function notify(message, level)
	vim.notify(message, level or vim.log.levels.WARN)
end

local function has_lsp(bufnr)
	local clients = vim.lsp.get_clients({ bufnr = bufnr })
	return clients and #clients > 0
end

local function should_ignore(symbol)
	if ignore_list[symbol] then
		return true
	end
	for _, item in ipairs(config.ignored or {}) do
		if item == symbol then
			return true
		end
	end
	return false
end

local function select_symbol_in_line(line, col)
	if not line or line == "" then
		return nil
	end

	local candidates = {}
	for s, ident in line:gmatch("()([%a_][%w_]*)") do
		local start = s - 1
		local finish = start + #ident - 1
		if not should_ignore(ident) then
			table.insert(candidates, { ident = ident, start = start, finish = finish })
		end
	end

	if #candidates == 0 then
		return nil
	end

	for _, cand in ipairs(candidates) do
		if col >= cand.start and col <= cand.finish then
			return cand.ident, cand.start
		end
	end

	local last = candidates[#candidates]
	return last.ident, last.start
end

local function position_params(bufnr, line, col)
	return {
		textDocument = { uri = vim.uri_from_bufnr(bufnr) },
		position = { line = line, character = col },
	}
end

local function is_duplicate(src_buf, src_start_line)
	for _, frame in ipairs(state.stack) do
		if frame.src_buf == src_buf and frame.src_start_line == src_start_line then
			return true
		end
	end
	return false
end

local function open_from_location(src_buf, line, col, parent_win)
	local params = position_params(src_buf, line, col)

	resolver.resolve(src_buf, params, function(result)
		if not result then
			notify("Go type hover: no type definition found")
			return
		end

		if is_duplicate(result.bufnr, result.start_line) then
			notify("Go type hover: type is already open", vim.log.levels.INFO)
			return
		end

		local extracted = extractor.extract(result.bufnr, result.start_line, result.end_line)
		if not extracted or #extracted.lines == 0 then
			notify("Go type hover: unable to extract type definition")
			return
		end

		local float_opts = vim.tbl_deep_extend("force", {}, config.float or {})

		local win_width = math.floor(float_opts.width or float_opts.max_width or 80)
		float_opts.width = win_width

		-- need to calculate height based on content and wrapping (usually comments in the struct)
		local content_h = 0
		for _, l in ipairs(extracted.lines) do
			local text_w = vim.fn.strdisplaywidth(l)

			if text_w == 0 then
				content_h = content_h + 1
			else
				content_h = content_h + math.ceil(text_w / win_width)
			end
		end

		local screen_h = vim.o.lines - vim.o.cmdheight
		local screen_w = vim.o.columns
		local max_h_conf = float_opts.max_height

		local limit_h = screen_h - 2
		if max_h_conf and max_h_conf > 0 and max_h_conf < limit_h then
			limit_h = max_h_conf
		end

		local final_height = math.min(content_h, limit_h)
		float_opts.height = math.floor(math.max(1, final_height))

		float_opts.relative = "editor"

		if not parent_win then
			local win_pos = vim.api.nvim_win_get_position(0)
			local cursor = vim.api.nvim_win_get_cursor(0)
			float_opts.row = win_pos[1] + cursor[1]
			float_opts.col = win_pos[2] + cursor[2]
		else
			if vim.api.nvim_win_is_valid(parent_win) then
				local parent_pos = vim.api.nvim_win_get_position(parent_win)
				local off_r = config.offset.row or 1
				local off_c = config.offset.col or 2

				float_opts.row = parent_pos[1] + off_r
				float_opts.col = parent_pos[2] + off_c
			else
				float_opts.row = 1
				float_opts.col = 1
			end
		end

		if float_opts.row + float_opts.height > screen_h then
			float_opts.row = math.max(0, screen_h - float_opts.height - 1)
		end

		if float_opts.col + float_opts.width > screen_w then
			float_opts.col = math.max(0, screen_w - float_opts.width - 2)
		end

		float_opts.row = math.floor(float_opts.row)
		float_opts.col = math.floor(float_opts.col)

		local actions = {
			enter = function()
				local cur_win = vim.api.nvim_get_current_win()
				local frame = state.get_frame(cur_win)
				if not frame then
					return
				end

				local cursor = vim.api.nvim_win_get_cursor(cur_win)
				local row = cursor[1]
				local col = cursor[2]

				local lines = vim.api.nvim_buf_get_lines(frame.buf, row - 1, row, false)
				if not lines or #lines == 0 then
					return
				end

				local symbol, ident_col = select_symbol_in_line(lines[1], col)
				if not symbol then
					return
				end

				local src_line = frame.src_start_line + (row - 1)
				local src_col = ident_col

				open_from_location(frame.src_buf, src_line, src_col, cur_win)
			end,
			back = function()
				state.close_top()
			end,
			close_all = function()
				state.close_all()
			end,
		}

		local buf, win = float.open(extracted.lines, float_opts, actions)

		if win and vim.api.nvim_win_is_valid(win) then
			vim.wo[win].wrap = true
			vim.wo[win].breakindent = true
		end

		local frame = {
			win = win,
			buf = buf,
			src_buf = result.bufnr,
			src_start_line = extracted.start_line,
			symbol = result.symbol,
		}
		state.push(frame)
	end)
end

function M.hover()
	local bufnr = vim.api.nvim_get_current_buf()
	if vim.bo[bufnr].filetype ~= "go" then
		notify("Go type hover: not a Go buffer")
		return
	end

	if not has_lsp(bufnr) then
		notify("Go type hover: no LSP client attached")
		return
	end

	state.close_all()
	local cursor = vim.api.nvim_win_get_cursor(0)
	open_from_location(bufnr, cursor[1] - 1, cursor[2], nil)
end

function M.setup(opts)
	config = vim.tbl_deep_extend("force", vim.deepcopy(default_config), opts or {})

	if opts and opts.ignored then
		for _, v in ipairs(opts.ignored) do
			ignore_list[v] = true
		end
	end

	if active_keymap then
		pcall(vim.keymap.del, "n", active_keymap)
		active_keymap = nil
	end

	if config.keymap and config.keymap ~= "" then
		vim.keymap.set("n", config.keymap, function()
			require("go_type_hover").hover()
		end, { desc = "Go type hover" })
		active_keymap = config.keymap
	end
end

return M
