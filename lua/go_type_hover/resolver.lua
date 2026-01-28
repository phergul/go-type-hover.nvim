local M = {}

---Normalizes an LSP location item
---@param item table|nil The LSP location item
---@return table|nil The normalized location
local function normalize_location(item)
	if not item then
		return nil
	end

	if item.targetUri then
		return {
			uri = item.targetUri,
			range = item.targetRange or item.targetSelectionRange or item.range,
		}
	end

	if item.uri then
		return {
			uri = item.uri,
			range = item.range,
		}
	end

	return nil
end

---Extracts the first location from an LSP result
---@param result table|nil The LSP result
---@return table|nil The first normalized location
local function first_location(result)
	if not result then
		return nil
	end

	if vim.islist(result) then
		if #result == 0 then
			return nil
		end
		return normalize_location(result[1])
	end

	return normalize_location(result)
end

---Resolves a specific LSP method
---@param bufnr number The buffer number
---@param params table The LSP parameters
---@param method string The LSP method name
---@param callback function The callback function
local function resolve_method(bufnr, params, method, callback)
	local clients = vim.lsp.get_clients({ bufnr = bufnr })
	local pending = #clients
	local done = false

	if pending == 0 then
		callback(nil)
		return
	end

	vim.lsp.buf_request(bufnr, method, params, function(_, result)
		if done then
			return
		end

		local location = first_location(result)
		if location then
			done = true
			callback(location)
			return
		end

		pending = pending - 1
		if pending <= 0 and not done then
			callback(nil)
		end
	end)
end

---Resolves the type definition for the given parameters using LSP
---@param bufnr number The buffer number
---@param params table The LSP parameters (textDocument, position)
---@param callback function The callback function to receive the result
function M.resolve(bufnr, params, callback)
	resolve_method(bufnr, params, "textDocument/typeDefinition", function(location)
		if location then
			callback(M.normalize(location))
			return
		end

		resolve_method(bufnr, params, "textDocument/definition", function(fallback)
			if not fallback then
				callback(nil)
				return
			end
			callback(M.normalize(fallback))
		end)
	end)
end

---Normalizes the LSP location result
---@param location table The LSP location object
---@return table|nil The normalized result containing bufnr, start_line, and uri, or nil
function M.normalize(location)
	if not location or not location.uri then
		return nil
	end

	local bufnr = vim.uri_to_bufnr(location.uri)
	if not vim.api.nvim_buf_is_loaded(bufnr) then
		pcall(vim.fn.bufload, bufnr)
	end

	local range = location.range
	local start_line = 0

	if range and range.start then
		start_line = range.start.line or 0
	end

	return {
		bufnr = bufnr,
		start_line = start_line,
		uri = location.uri,
	}
end

return M
