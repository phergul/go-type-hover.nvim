describe("hover symbol selection", function()
	local bufnr
	local line
	local original_get_clients
	local state = require("go_type_hover.state")

	local function load_with_modules(mocks)
		local original_modules = {}
		for module_name, module_impl in pairs(mocks) do
			original_modules[module_name] = package.loaded[module_name]
			package.loaded[module_name] = module_impl
		end

		package.loaded["go_type_hover"] = nil
		local mod = require("go_type_hover")
		package.loaded["go_type_hover"] = nil

		for module_name, old_module in pairs(original_modules) do
			package.loaded[module_name] = old_module
		end

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
		state.close_all()
	end)

	after_each(function()
		package.loaded["go_type_hover"] = nil
		if original_get_clients then
			vim.lsp.get_clients = original_get_clients
		end
		state.close_all()
		if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
			vim.api.nvim_buf_delete(bufnr, { force = true })
		end
	end)

	it("uses first custom type when cursor is on line whitespace", function()
		local captured
		local hover = load_with_modules({
			["go_type_hover.resolver"] = {
				resolve = function(_, params, cb)
					captured = params
					cb(nil)
				end,
			},
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
		local hover = load_with_modules({
			["go_type_hover.resolver"] = {
				resolve = function(_, params, cb)
					captured = params
					cb(nil)
				end,
			},
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

	it("does not keep footer metadata when show_footer is false", function()
		local hover = load_with_modules({
			["go_type_hover.resolver"] = {
				resolve = function(_, _, cb)
					cb({ bufnr = bufnr, start_line = 0 })
				end,
			},
			["go_type_hover.extractor"] = {
				extract = function()
					return { lines = { "type TypeOne struct {}" }, start_line = 0 }
				end,
			},
			["go_type_hover.float"] = {
				open = function()
					return bufnr, -1
				end,
			},
		})
		hover.setup({
			keymap = "",
			float = { show_footer = false },
		})

		hover.hover()

		assert.are.same(1, #state.stack)
		assert.is_nil(state.stack[1].footer)
	end)
end)
