local extractor = require("go_type_hover.extractor")

describe("extractor", function()
	local bufnr

	before_each(function()
		local path = "tests/test_data.go"
		local lines = vim.fn.readfile(path)
		bufnr = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
		vim.bo[bufnr].filetype = "go"

		-- Ensure Tree-sitter parser is loaded
		local ok = pcall(vim.treesitter.start, bufnr, "go")
		if not ok then
			pending("Tree-sitter 'go' parser not available")
		end
	end)

	after_each(function()
		if bufnr then
			vim.api.nvim_buf_delete(bufnr, { force = true })
		end
	end)

	it("extracts SimpleStruct", function()
		-- 0-indexed line 3: type SimpleStruct struct {
		local res = extractor.extract(bufnr, 3)
		assert.is_not_nil(res)
		assert.are.same(3, res.start_line)
		assert.are.same("type SimpleStruct struct {", res.lines[1])
		assert.are.same("	Field int", res.lines[2])
		assert.are.same("}", res.lines[3])
	end)

	it("extracts GroupedStruct", function()
		-- 0-indexed line 9: GroupedStruct struct {
		local res = extractor.extract(bufnr, 9)
		assert.is_not_nil(res)
		-- Tree-sitter extraction starts at the node, so no leading whitespace on first line
		assert.are.same("GroupedStruct struct {", res.lines[1])
		assert.are.same("		Name string", res.lines[2])
		assert.are.same("	}", res.lines[3])
	end)

	it("extracts NestedStruct", function()
		-- 0-indexed line 15: type NestedStruct struct {
		local res = extractor.extract(bufnr, 15)
		assert.is_not_nil(res)
		assert.are.same("type NestedStruct struct {", res.lines[1])
		assert.is_true(#res.lines >= 4)
	end)

	it("extracts Interface", function()
		-- 0-indexed line 25: type Doer interface {
		local res = extractor.extract(bufnr, 25)
		assert.is_not_nil(res)
		assert.are.same("type Doer interface {", res.lines[1])
		assert.are.same("	Do() error", res.lines[2])
		assert.are.same("}", res.lines[3])
	end)

	it("extracts type alias (MyInt)", function()
		-- 0-indexed line 22: type MyInt int
		local res = extractor.extract(bufnr, 22)
		assert.is_not_nil(res)
		assert.are.same("type MyInt int", res.lines[1])
		assert.are.same(1, #res.lines)
	end)

	it("extracts documentation when requested", function()
		-- SimpleStruct has a comment: // SimpleStruct is a basic struct
		local res = extractor.extract(bufnr, 3, true)
		assert.is_not_nil(res)
		assert.are.same("// SimpleStruct is a basic struct", res.lines[1])
		assert.are.same("type SimpleStruct struct {", res.lines[2])
	end)

	it("does not extract documentation when disabled", function()
		local res = extractor.extract(bufnr, 3, false)
		assert.is_not_nil(res)
		assert.are.same("type SimpleStruct struct {", res.lines[1])
	end)
end)
