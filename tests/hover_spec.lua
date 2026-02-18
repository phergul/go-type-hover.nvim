describe("hover symbol selection", function()
	local bufnr
	local line
	local original_get_clients

	local function load_with_resolver(resolver_mock)
		local original_resolver = package.loaded["go_type_hover.resolver"]
		package.loaded["go_type_hover.resolver"] = resolver_mock
		package.loaded["go_type_hover"] = nil
		local mod = require("go_type_hover")
		package.loaded["go_type_hover"] = nil
		package.loaded["go_type_hover.resolver"] = original_resolver
		return mod
	end

	before_each(function()
		line = "    map[TypeOne]TypeTwo"
		bufnr = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { line })
		vim.bo[bufnr].filetype = "go"
		vim.api.nvim_set_current_buf(bufnr)

		original_get_clients = vim.lsp.get_clients
		vim.lsp.get_clients = function(_)
			return { { id = 1 } }
		end
	end)

	after_each(function()
		package.loaded["go_type_hover"] = nil
		if original_get_clients then
			vim.lsp.get_clients = original_get_clients
		end
		if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
			vim.api.nvim_buf_delete(bufnr, { force = true })
		end
	end)

	it("uses first custom type when cursor is on line whitespace", function()
		local captured
		local hover = load_with_resolver({
			resolve = function(_, params, cb)
				captured = params
				cb(nil)
			end,
		})
		hover.setup({ keymap = "" })

		vim.api.nvim_win_set_cursor(0, { 1, 0 })
		hover.hover()

		local type_one_col = line:find("TypeOne", 1, true) - 1
		assert.is_not_nil(captured)
		assert.are.same(type_one_col, captured.position.character)
	end)

	it("requires cursor on second custom type to resolve second type", function()
		local captured
		local hover = load_with_resolver({
			resolve = function(_, params, cb)
				captured = params
				cb(nil)
			end,
		})
		hover.setup({ keymap = "" })

		local type_one_col = line:find("TypeOne", 1, true) - 1
		local type_two_col = line:find("TypeTwo", 1, true) - 1

		vim.api.nvim_win_set_cursor(0, { 1, type_two_col - 1 })
		hover.hover()
		assert.are.same(type_one_col, captured.position.character)

		vim.api.nvim_win_set_cursor(0, { 1, type_two_col })
		hover.hover()
		assert.are.same(type_two_col, captured.position.character)
	end)
end)
