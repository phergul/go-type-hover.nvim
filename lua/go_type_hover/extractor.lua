local M = {}

---Traverses the node tree upwards to find a type specification or declaration node
---@param node TSNode|nil The starting node
---@return TSNode|nil The found type node or nil
local function find_type_node(node)
	while node do
		local type = node:type()
		if type == "type_spec" or type == "type_declaration" then
			return node
		end
		node = node:parent()
	end
	return nil
end

---Extracts the type definition at the specified location using Tree-sitter
---@param bufnr number The buffer number
---@param start_line number The 0-based start line of the definition
---@param include_docs boolean|nil Whether to include preceding documentation comments
---@return table|nil The extracted lines and start line, or nil if failed
function M.extract(bufnr, start_line, include_docs)
	local parser = vim.treesitter.get_parser(bufnr, "go")
	if not parser then
		return nil
	end

	local tree = parser:parse()[1]
	if not tree then
		return nil
	end

	local root = tree:root()

	local line_content = vim.api.nvim_buf_get_lines(bufnr, start_line, start_line + 1, false)[1]
	if not line_content then
		return nil
	end

	local col = line_content:find("%S")
	if not col then
		return nil
	end
	col = col - 1

	local node = root:named_descendant_for_range(start_line, col, start_line, col)

	local type_node = find_type_node(node)
	if not type_node then
		return nil
	end

	local start_row, _, _, _ = type_node:range()
	local text = vim.treesitter.get_node_text(type_node, bufnr)
	local lines = vim.split(text, "\n")

	if include_docs then
		local prev = type_node:prev_sibling()
		local comments = {}
		while prev and prev:type() == "comment" do
			local comment_text = vim.treesitter.get_node_text(prev, bufnr)
			table.insert(comments, 1, comment_text)
			start_row, _, _, _ = prev:range()
			prev = prev:prev_sibling()
		end

		if #comments > 0 then
			local combined = {}
			for _, c in ipairs(comments) do
				table.insert(combined, c)
			end
			for _, l in ipairs(lines) do
				table.insert(combined, l)
			end
			lines = combined
		end
	end

	return { lines = lines, start_line = start_row }
end

return M
