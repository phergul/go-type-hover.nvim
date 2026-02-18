describe("resolver", function()
	local resolver
	local original_buf_request

	before_each(function()
		package.loaded["go_type_hover.resolver"] = nil
		resolver = require("go_type_hover.resolver")
		original_buf_request = vim.lsp.buf_request
	end)

	after_each(function()
		vim.lsp.buf_request = original_buf_request
	end)

	it("falls back to definition when one typeDefinition response is empty", function()
		local test_buf = vim.api.nvim_create_buf(false, true)
		local uri = vim.uri_from_bufnr(test_buf)
		local calls = 0

		vim.lsp.buf_request = function(_, method, _, handler)
			calls = calls + 1
			if method == "textDocument/typeDefinition" then
				handler(nil, nil, { client_id = 1 })
				return { [1] = 11 }
			end

			handler(nil, { uri = uri, range = { start = { line = 4 } } }, { client_id = 1 })
			return { [1] = 12 }
		end

		local result
		resolver.resolve(test_buf, {}, function(res)
			result = res
		end)

		assert.is_true(calls >= 2)
		assert.is_not_nil(result)
		assert.is_true(type(result.bufnr) == "number")
		assert.are.same(4, result.start_line)

		vim.api.nvim_buf_delete(test_buf, { force = true })
	end)
end)
