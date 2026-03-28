-- vis-treesitter plugin init file

-- NOTE: currently this reparses the whole *view* each time
-- since vis does not currently expose a finegrained 
-- "text modified" event to its Lua API

-- IMPORTANT: add a plugin setting to control which language take preccedence
-- like .prefer = [ "lua", "typst" ... ]
-- which will try first the tree-sitter parser and fallback to lpeg

local path = debug.getinfo(1, "S").source:match("^@?(.*)/")
if path then
	package.cpath = path .. "/?.so;" .. package.cpath
end

local ts_ok, ts = pcall(require, "ts")
if not ts_ok then
	if vis then vis:info("vis-treesitter: failed to load native module") end
	return
end

if vis then
	vis.ts = ts
end

local M = { ts = ts }

M.default_tags = {
	'whitespace', 'comment', 'string', 'number', 'keyword', 'identifier', 'operator', 'error',
	'preprocessor', 'constant', 'variable', 'function', 'class', 'type', 'label', 'regex', 'embedded',
	'function.builtin', 'constant.builtin', 'function.method', 'tag', 'attribute', 'variable.builtin',
	'heading', 'bold', 'italic', 'underline', 'code', 'link', 'reference', 'annotation', 'list'
}

M.capture_to_tag = {
	-- Keywords
	['keyword']                     = 'keyword',
	['keyword.function']            = 'keyword',
	['keyword.operator']            = 'operator',
	['keyword.return']              = 'keyword',
	['keyword.conditional']         = 'keyword',
	['keyword.repeat']              = 'keyword',
	['keyword.import']              = 'keyword',
	['keyword.exception']           = 'keyword',
	['keyword.modifier']            = 'keyword',
	['keyword.type']                = 'keyword',
	['keyword.coroutine']           = 'keyword',
	['keyword.directive']           = 'preprocessor',
	['keyword.storage.type']        = 'keyword',
	['keyword.control']             = 'keyword',
	['keyword.control.conditional'] = 'keyword',
	['keyword.control.repeat']      = 'keyword',
	['keyword.control.import']      = 'keyword',

	-- Strings
	['string']                      = 'string',
	['string.special']              = 'string',
	['string.escape']               = 'constant.builtin',
	['string.regex']                = 'regex',
	['string.special.url']          = 'link',

	-- Comments & Documentation
	['comment']                     = 'comment',
	['comment.documentation']       = 'annotation',

	-- numbers
	['number']                      = 'number',
	['number.float']                = 'number',

	-- constants + booleans
	['boolean']                     = 'constant.builtin',
	['character']                   = 'string',
	['character.special']           = 'constant.builtin',
	['constant']                    = 'constant',
	['constant.builtin']            = 'constant.builtin',
	['constant.builtin.boolean']    = 'constant.builtin',
	['constant.macro']              = 'constant',
	['constant.numeric']            = 'number',
	['constant.character']          = 'string',
	['constant.character.escape']   = 'constant.builtin',

	-- funcs
	['function']                    = 'function',
	['function.call']               = 'function',
	['function.builtin']            = 'function.builtin',
	['function.method']             = 'function.method',
	['function.method.call']        = 'function.method',
	['function.macro']              = 'function',
	['constructor']                 = 'function',

	-- tyypes + classes
	['type']                        = 'type',
	['type.builtin']                = 'type',
	['type.definition']             = 'type',
	['type.qualifier']              = 'keyword',
	['class']                       = 'class',
	['namespace']                   = 'class',
	['module']                      = 'class',

	-- vars + identifiers
	['variable']                    = 'variable',
	['variable.builtin']            = 'variable.builtin',
	['variable.parameter']          = 'variable',
	['variable.member']             = 'variable',
	['property']                    = 'identifier',

	-- ops + punctuation
	['operator']                    = 'operator',
	['punctuation.bracket']         = 'operator',
	['punctuation.delimiter']       = 'operator',
	['punctuation.special']         = 'operator',
	['punctuation']                 = 'operator',

	-- labels + attrs
	['label']                       = 'label',
	['attribute']                   = 'attribute',
	['tag']                         = 'tag',
	['tag.attribute']               = 'attribute',
	['tag.delimiter']               = 'operator',

	-- preprocessor
	['preprocessor']                = 'preprocessor',
	['define']                      = 'preprocessor',
	['include']                     = 'preprocessor',

	['embedded']                    = 'embedded',

	['error']                       = 'error',

	-- markup
	['markup.raw']                  = 'code',
	['markup.raw.block']            = 'code',
	['markup.raw.inline']           = 'code',
	['markup.italic']               = 'italic',
	['markup.bold']                 = 'bold',
	['markup.underline']            = 'underline',
	['markup.heading']              = 'heading',
	['markup.heading.marker']       = 'heading',
	['markup.heading.1']            = 'heading',
	['markup.heading.2']            = 'heading',
	['markup.heading.3']            = 'heading',
	['markup.heading.4']            = 'heading',
	['markup.heading.5']            = 'heading',
	['markup.heading.6']            = 'heading',
	['markup.list']                 = 'list',
	['markup.list.checked']         = 'list',
	['markup.list.unchecked']       = 'list',
	['markup.quote']                = 'comment',
	['markup.link']                 = 'link',
	['markup.link.url']             = 'link',
	['markup.link.label']           = 'reference',
}

local parsers = {}
local queries = {}

local grammar_search_paths = {
	'/usr/lib/tree-sitter/',
	'/usr/local/lib/tree-sitter/',
}

local home = os.getenv('HOME')
if home then
	table.insert(grammar_search_paths, 1, home .. '/.local/lib/tree-sitter/')
end

local query_search_paths = {}
if path then
	table.insert(query_search_paths, path .. '/queries/')
end

function M.add_grammar_path(p)
	if p:sub(-1) ~= '/' then p = p .. '/' end
	table.insert(grammar_search_paths, 1, p)
end

function M.add_query_path(p)
	if p:sub(-1) ~= '/' then p = p .. '/' end
	table.insert(query_search_paths, 1, p)
end

function M.reset_caches()
	parsers = {}
	queries = {}
end

local function find_grammar(lang)
	for _, dir in ipairs(grammar_search_paths) do
		local p = dir .. lang .. '.so'
		local f = io.open(p, 'r')
		if f then
			f:close()
			return p
		end
	end
	return nil
end

local function load_query_file(lang)
	for _, dir in ipairs(query_search_paths) do
		local p = dir .. lang .. '.scm'
		local f = io.open(p, 'r')
		if f then
			local content = f:read('*a')
			f:close()
			return content
		end
	end
	return nil
end

function M.parser_for(lang)
	if parsers[lang] ~= nil then
		return parsers[lang] or nil
	end

	local grammar_path = find_grammar(lang)
	if not grammar_path then
		parsers[lang] = false
		return nil
	end

	local ok, parser = pcall(ts.load, grammar_path, lang)
	if not ok or not parser or not parser.parse_string then
		parsers[lang] = false
		return nil
	end

	parsers[lang] = parser
	return parser
end

local function get_query(lang)
	if queries[lang] ~= nil then
		return queries[lang] or nil
	end

	local query_src = load_query_file(lang)
	if not query_src then
		queries[lang] = false
		return nil
	end

	local parser = M.parser_for(lang)
	if not parser then
		queries[lang] = false
		return nil
	end

	local ok, query = pcall(parser.query, parser, query_src)
	if not ok or not query then
		queries[lang] = false
		return nil
	end

	queries[lang] = query
	return query
end

local function resolve_style(capture, tag_styles)
	if capture:sub(1, 1) == '@' then
		capture = capture:sub(2)
	end

	local tags = tag_styles or M.default_tags

	if tags then
		local t = capture
		while t do
			for id, name in ipairs(tags) do
				if name == t then return id end
			end
			t = t:match('^(.+)%.[^.]+$')
		end
	end

	local tag_name
	local prefix = capture
	while prefix do
		tag_name = M.capture_to_tag[prefix]
		if tag_name then break end
		prefix = prefix:match('^(.+)%.[^.]+$')
	end

	if not tag_name or not tags then return nil end

	for id, name in ipairs(tags) do
		if name == tag_name then return id end
	end

	return nil
end

function M.highlight(win)
	local lang = win._ts_lang
	if not lang then return end

	local parser = M.parser_for(lang)
	local query = get_query(lang)
	local viewport = win.viewport

	if not parser or not query or not viewport or not viewport.bytes then return end

	local vp_bytes = viewport.bytes
	local horizon_max = win.horizon or 32768
	local parse_start = math.max(0, vp_bytes.start - horizon_max)
	local parse_end = math.min(win.file.size, vp_bytes.finish + horizon_max)

	local content = win.file:content(parse_start, parse_end - parse_start)
	if not content or #content == 0 then return end

	local ok, tree = pcall(parser.parse_string, parser, content)
	if not ok or not tree then return end

	win._ts_tree = tree

	local root = tree:root()
	if not root then return end

	local tag_styles = M.default_tags
	if vis.lexers and vis.lexers.load then
		local lex_ok, lexer = pcall(vis.lexers.load, win.syntax, nil, true)
		if lex_ok and lexer and lexer._TAGS then
			tag_styles = lexer._TAGS
		end
	end

	local cap_ok = pcall(function()
		for capture_node, capture_name in query:capture(root) do
			if not capture_name or not capture_node then goto continue end

			local start_byte, end_byte
			if capture_node.start_byte_offset then
				start_byte, end_byte = capture_node:start_byte_offset(), capture_node:end_byte_offset()
			elseif capture_node.start_byte then
				start_byte, end_byte = capture_node:start_byte(), capture_node:end_byte()
			elseif capture_node.start_index then
				start_byte, end_byte = capture_node:start_index() - 1, capture_node:end_index()
			else
				goto continue
			end

			local abs_start = parse_start + start_byte
			local abs_end = parse_start + end_byte - 1

			if abs_end >= vp_bytes.start and abs_start <= vp_bytes.finish then
				local style_id = resolve_style(capture_name, tag_styles)
				if style_id then
					win:style(style_id, abs_start, abs_end)
				end
			end
			::continue::
		end
	end)

	if not cap_ok then
		win._ts_lang = nil
	end
end

function M.clear_cache(win)
	win._ts_tree = nil
	win._ts_lang = nil
end

if vis then
	vis.treesitter = M

	if vis.lexers and vis.lexers.load then
		local old_load = vis.lexers.load
		local dummy_cache = {} -- NOTE: make sure _TAGS arrays aren't re-instantiated and lost
		vis.lexers.load = function(name, alt_name, cache)
			if name and M.parser_for(name) then
				if dummy_cache[name] then return dummy_cache[name] end
				local tags_copy = {}
				for i, tag in ipairs(M.default_tags) do
					tags_copy[i] = tag
					tags_copy[tag] = i
				end
				local dummy = { 
					_name = name, 
					_TAGS = tags_copy, 
					_rules = { {"comment", "comment"}, comment = "comment" },
					lex = function(...) return {} end 
				}
				dummy_cache[name] = dummy
				return dummy
			end
			local ok, lex = pcall(old_load, name, alt_name, cache)
			if ok then return lex else return nil end
		end
	end

	local function detect_ts_lang(win)
		if win.syntax and M.parser_for(win.syntax) then
			return win.syntax
		end
		
		local file = win.file
		if not file then return nil end
		local name = file.name and file.name:match("[^/]+$")
		if not name then return nil end
		
		local ftdetect = vis.ftdetect
		if ftdetect then
			if ftdetect.filenames and ftdetect.filenames[name] then
				return ftdetect.filenames[name]
			end
			
			local ext = name:match("%.([^.]+)$")
			if ext and ftdetect.extensions and ftdetect.extensions[ext] then
				return ftdetect.extensions[ext]
			end
			
			if ext and M.parser_for(ext) then
				return ext
			end
		end
		return nil
	end

	vis.events.subscribe(vis.events.WIN_OPEN, function(win)
		local lang = detect_ts_lang(win)
		if lang and M.parser_for(lang) then
			win._ts_lang = lang
			if not win.syntax then
				win.syntax = lang
				vis:info("")
				
				if M.default_tags and vis.lexers then
					for id, token_name in ipairs(M.default_tags) do
						local style = vis.lexers['STYLE_' .. token_name:upper():gsub("%.", "_")] or ''
						if type(style) == 'table' then
							local s
							if style.attr then s = tostring(style.attr) end
							if style.fore then s = (s and s .. ',' or '') .. 'fore:' .. tostring(style.fore) end
							if style.back then s = (s and s .. ',' or '') .. 'back:' .. tostring(style.back) end
							style = s
						end
						if style ~= '' then win:style_define(id, style) end
					end
				end
			end
		end
	end)

	vis.events.subscribe(vis.events.WIN_HIGHLIGHT, function(win)
		if win._ts_lang then
			M.highlight(win)
		end
	end)
end

return M


