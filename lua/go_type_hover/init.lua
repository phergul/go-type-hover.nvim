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
		-- whether to show header and footer
		show_header = true,
		show_footer = true,
	},

	-- offset from the anchor position
	offset = { row = 1, col = 2 },

	-- identifiers to ignore
	ignored = {},

	-- whether to show documentation comments
	show_docs = true,
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

---Sends a notification message
---@param message string The message to display
---@param level number|nil The notification level (default: WARN)
local function notify(message, level)
	vim.notify(message, level or vim.log.levels.WARN)
end

---Checks if an LSP client is attached to the buffer
---@param bufnr number The buffer number
---@return boolean True if LSP is attached
local function has_lsp(bufnr)
	local clients = vim.lsp.get_clients({ bufnr = bufnr })
	return clients and #clients > 0
end

---Checks if a symbol should be ignored
---@param symbol string The symbol name
---@return boolean True if the symbol should be ignored
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

---Finds a symbol in the given line for the specified column
---@param bufnr number The buffer number
---@param row number The 0-based row index
---@param col number The 0-based column index
---@return string|nil, number|nil The found symbol and its start column, or nil
local function find_symbol(bufnr, row, col)
	local candidates = {}
	local used_ts = false

	local parser_ok, parser = pcall(vim.treesitter.get_parser, bufnr, "go")
	if parser_ok and parser then
		local tree = parser:parse()[1]
		if tree then
			local root = tree:root()
			local line_node = root:named_descendant_for_range(row, 0, row, -1)

			if line_node then
				local function traverse(node)
					if not node then
						return
					end
					local s_row, s_col, e_row, e_col = node:range()
					if s_row > row or e_row < row then
						return
					end

					local type = node:type()
					if type == "type_identifier" then
						local text = vim.treesitter.get_node_text(node, bufnr)
						if not should_ignore(text) then
							local is_dup = false
							for _, c in ipairs(candidates) do
								if c.start == s_col and c.finish == e_col - 1 then
									is_dup = true
									break
								end
							end
							if not is_dup then
								table.insert(candidates, { ident = text, start = s_col, finish = e_col - 1 })
							end
						end
					end

					for child in node:iter_children() do
						traverse(child)
					end
				end
				traverse(line_node)
				if #candidates > 0 then
					used_ts = true
				end
			end
		end
	end

	if not used_ts then
		local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
		if not line or line == "" then
			return nil
		end
		for s, ident in line:gmatch("()([%a_][%w_]*)") do
			local start = s - 1
			local finish = start + #ident - 1
			if not should_ignore(ident) then
				table.insert(candidates, { ident = ident, start = start, finish = finish })
			end
		end
	end

	if #candidates == 0 then
		return nil
	end

	table.sort(candidates, function(a, b)
		if a.start == b.start then
			return a.finish < b.finish
		end
		return a.start < b.start
	end)

	for _, cand in ipairs(candidates) do
		if col >= cand.start and col <= cand.finish then
			return cand.ident, cand.start
		end
	end

	local first = candidates[1]
	return first.ident, first.start
end

---Constructs LSP position parameters
---@param bufnr number The buffer number
---@param line number The 0-based line number
---@param col number The 0-based column number
---@return table The LSP textDocumentPositionParams
local function position_params(bufnr, line, col)
	return {
		textDocument = { uri = vim.uri_from_bufnr(bufnr) },
		position = { line = line, character = col },
	}
end

---Checks if a type definition is already open in the stack
---@param src_buf number The source buffer number
---@param src_start_line number The start line of the definition
---@return boolean True if the definition is already open
local function is_duplicate(src_buf, src_start_line)
	for _, frame in ipairs(state.stack) do
		if frame.src_buf == src_buf and frame.src_start_line == src_start_line then
			return true
		end
	end
	return false
end

---Opens the type definition from the given location in a floating window
---@param src_buf number The source buffer number
---@param line number The 0-based line number
---@param col number The 0-based column number
---@param parent_win number|nil The parent window handle
---@param symbol_name string|nil The name of the symbol being opened
local function open_from_location(src_buf, line, col, parent_win, symbol_name)
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

		local extracted = extractor.extract(result.bufnr, result.start_line, config.show_docs)
		if not extracted or #extracted.lines == 0 then
			notify("Go type hover: unable to extract type definition")
			return
		end

		local float_opts = vim.tbl_deep_extend("force", {}, config.float or {})

		local win_width = math.floor(float_opts.width or float_opts.max_width or 80)
		float_opts.width = win_width

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

		local title_parts = {}
		for _, frame in ipairs(state.stack) do
			if frame.symbol then
				table.insert(title_parts, frame.symbol)
			end
		end

		local current_symbol = symbol_name
		if not current_symbol then
			for _, l in ipairs(extracted.lines) do
				if not l:match("^%s*//") then
					local name = l:match("type%s+([%w_]+)")
					if name then
						current_symbol = name
					end
					break
				end
			end
		end

		if current_symbol then
			table.insert(title_parts, current_symbol)
		end

		local title = " " .. table.concat(title_parts, " > ") .. " "
		if #title_parts == 0 then
			title = " Type Definition "
		end

		local footer = " l Enter | h Back | e Jump | q Close "

		float_opts.title = title
		float_opts.footer = footer

		for _, frame in ipairs(state.stack) do
			if frame.win and vim.api.nvim_win_is_valid(frame.win) then
				vim.api.nvim_win_set_config(frame.win, { title = "", footer = "" })
			end
		end

		local off_r = config.offset.row or 1
		local off_c = config.offset.col or 2

		if not parent_win then
			float_opts.relative = "editor"
			if config.anchor == "editor" then
				float_opts.row = off_r
				float_opts.col = off_c
			else
				local win_pos = vim.api.nvim_win_get_position(0)
				local cursor = vim.api.nvim_win_get_cursor(0)
				float_opts.row = win_pos[1] + cursor[1] + off_r - 1
				float_opts.col = win_pos[2] + cursor[2] + off_c
			end
		else
			if vim.api.nvim_win_is_valid(parent_win) then
				local parent_pos = vim.api.nvim_win_get_position(parent_win)
				float_opts.relative = "editor"
				float_opts.row = parent_pos[1] + off_r
				float_opts.col = parent_pos[2] + off_c
			else
				float_opts.relative = "editor"
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

				local symbol, ident_col = find_symbol(frame.buf, row - 1, col)
				if not symbol then
					return
				end

				local src_line = frame.src_start_line + (row - 1)
				local src_col = ident_col

				open_from_location(frame.src_buf, src_line, src_col, cur_win, symbol)
			end,
			back = function()
				state.close_top()
			end,
			close_all = function()
				state.close_all()
			end,
			jump = function()
				state.close_all()
				if vim.api.nvim_buf_is_valid(result.bufnr) then
					vim.api.nvim_set_current_buf(result.bufnr)
					vim.api.nvim_win_set_cursor(0, { result.start_line + 1, 0 })
				end
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
			symbol = current_symbol,
			title = title,
			footer = footer,
		}
		state.push(frame)
	end)
end

---Triggers the type hover functionality for the symbol under the cursor
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
	local symbol, ident_col = find_symbol(bufnr, cursor[1] - 1, cursor[2])
	local request_col = ident_col or cursor[2]
	open_from_location(bufnr, cursor[1] - 1, request_col, nil, symbol)
end

---Sets up the plugin with the given options
---@param opts table|nil Configuration options
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
