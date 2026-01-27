local M = {}

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
	local end_line = 0

	if range and range.start then
		start_line = range.start.line or 0
	end
	if range and range["end"] then
		end_line = range["end"].line or start_line
	else
		end_line = start_line
	end

	return {
		bufnr = bufnr,
		start_line = start_line,
		end_line = end_line,
		uri = location.uri,
	}
end

return M
