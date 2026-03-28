#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <dlfcn.h>
#include <tree_sitter/api.h>
#include <string.h>

#define VIS_TS_PARSER    "vis.ts.parser"
#define VIS_TS_TREE      "vis.ts.tree"
#define VIS_TS_NODE      "vis.ts.node"
#define VIS_TS_QUERY     "vis.ts.query"

typedef struct {
	TSParser *parser;
	const TSLanguage *lang;
	void *handle;
} TsParser;

typedef struct {
	TSTree *tree;
} TsTree;

typedef struct {
	TSNode node;
} TsNode;

typedef struct {
	TSQuery *query;
} TsQuery;

static int ts_load(lua_State *L) {
	const char *path = luaL_checkstring(L, 1);
	const char *lang_name = luaL_checkstring(L, 2);

	void *handle = dlopen(path, RTLD_NOW | RTLD_GLOBAL);
	if (!handle) {
		lua_pushnil(L);
		lua_pushstring(L, dlerror());
		return 2;
	}

	char sym_name[128];
	snprintf(sym_name, sizeof(sym_name), "tree_sitter_%s", lang_name);
	const TSLanguage *(*lang_func)(void) = dlsym(handle, sym_name);
	if (!lang_func) {
		dlclose(handle);
		lua_pushnil(L);
		lua_pushfstring(L, "symbol %s not found", sym_name);
		return 2;
	}

	const TSLanguage *lang = lang_func();
	TSParser *parser = ts_parser_new();
	if (!ts_parser_set_language(parser, lang)) {
		ts_parser_delete(parser);
		dlclose(handle);
		lua_pushnil(L);
		lua_pushstring(L, "failed to set language");
		return 2;
	}

	TsParser *p = lua_newuserdata(L, sizeof(TsParser));
	p->parser = parser;
	p->lang = lang;
	p->handle = handle;
	luaL_getmetatable(L, VIS_TS_PARSER);
	lua_setmetatable(L, -2);
	return 1;
}

static int parser_gc(lua_State *L) {
	TsParser *p = luaL_checkudata(L, 1, VIS_TS_PARSER);
	if (p->parser) ts_parser_delete(p->parser);
	if (p->handle) dlclose(p->handle);
	return 0;
}

static int parser_parse_string(lua_State *L) {
	TsParser *p = luaL_checkudata(L, 1, VIS_TS_PARSER);
	size_t len;
	const char *str = luaL_checklstring(L, 2, &len);

	TSTree *tree = ts_parser_parse_string(p->parser, NULL, str, len);
	if (!tree) {
		lua_pushnil(L);
		return 1;
	}

	TsTree *t = lua_newuserdata(L, sizeof(TsTree));
	t->tree = tree;
	luaL_getmetatable(L, VIS_TS_TREE);
	lua_setmetatable(L, -2);
	return 1;
}

static int parser_query(lua_State *L) {
	TsParser *p = luaL_checkudata(L, 1, VIS_TS_PARSER);
	const char *source = luaL_checkstring(L, 2);

	uint32_t error_offset;
	TSQueryError error_type;
	TSQuery *query = ts_query_new(p->lang, source, strlen(source), &error_offset, &error_type);

	if (!query) {
		lua_pushnil(L);
		lua_pushfstring(L, "query error at %d (type %d)", error_offset, error_type);
		return 2;
	}

	TsQuery *q = lua_newuserdata(L, sizeof(TsQuery));
	q->query = query;
	luaL_getmetatable(L, VIS_TS_QUERY);
	lua_setmetatable(L, -2);
	return 1;
}

static int tree_gc(lua_State *L) {
	TsTree *t = luaL_checkudata(L, 1, VIS_TS_TREE);
	if (t->tree) ts_tree_delete(t->tree);
	return 0;
}

static int tree_root(lua_State *L) {
	TsTree *t = luaL_checkudata(L, 1, VIS_TS_TREE);
	TSNode root = ts_tree_root_node(t->tree);

	TsNode *n = lua_newuserdata(L, sizeof(TsNode));
	n->node = root;
	luaL_getmetatable(L, VIS_TS_NODE);
	lua_setmetatable(L, -2);
	return 1;
}

static int node_start_byte(lua_State *L) {
	TsNode *n = luaL_checkudata(L, 1, VIS_TS_NODE);
	lua_pushinteger(L, ts_node_start_byte(n->node));
	return 1;
}

static int node_end_byte(lua_State *L) {
	TsNode *n = luaL_checkudata(L, 1, VIS_TS_NODE);
	lua_pushinteger(L, ts_node_end_byte(n->node));
	return 1;
}

static int node_type(lua_State *L) {
	TsNode *n = luaL_checkudata(L, 1, VIS_TS_NODE);
	lua_pushstring(L, ts_node_type(n->node));
	return 1;
}

static int node_named_descendant_for_byte_range(lua_State *L) {
	TsNode *n = luaL_checkudata(L, 1, VIS_TS_NODE);
	uint32_t start = luaL_checkinteger(L, 2);
	uint32_t end = luaL_checkinteger(L, 3);
	TSNode desc = ts_node_named_descendant_for_byte_range(n->node, start, end);
	if (ts_node_is_null(desc)) {
		lua_pushnil(L);
		return 1;
	}
	TsNode *res = lua_newuserdata(L, sizeof(TsNode));
	res->node = desc;
	luaL_getmetatable(L, VIS_TS_NODE);
	lua_setmetatable(L, -2);
	return 1;
}

static int query_gc(lua_State *L) {
	TsQuery *q = luaL_checkudata(L, 1, VIS_TS_QUERY);
	if (q->query) ts_query_delete(q->query);
	return 0;
}

static int query_capture_iter(lua_State *L) {
	TSQueryCursor *cursor = lua_touserdata(L, lua_upvalueindex(1));
	TsQuery *q = luaL_checkudata(L, lua_upvalueindex(2), VIS_TS_QUERY);
	TSQueryMatch match;
	uint32_t capture_index;
	if (ts_query_cursor_next_capture(cursor, &match, &capture_index)) {
		TSQueryCapture capture = match.captures[capture_index];
		TsNode *res_node = lua_newuserdata(L, sizeof(TsNode));
		res_node->node = capture.node;
		luaL_getmetatable(L, VIS_TS_NODE);
		lua_setmetatable(L, -2);

		uint32_t name_len;
		const char *name = ts_query_capture_name_for_id(q->query, capture.index, &name_len);
		lua_pushlstring(L, name, name_len);
		return 2;
	}
	ts_query_cursor_delete(cursor);
	return 0;
}

static int query_capture(lua_State *L) {
	TsQuery *q = luaL_checkudata(L, 1, VIS_TS_QUERY);
	TsNode *n = luaL_checkudata(L, 2, VIS_TS_NODE);

	TSQueryCursor *cursor = ts_query_cursor_new();
	ts_query_cursor_exec(cursor, q->query, n->node);

	lua_pushlightuserdata(L, cursor);
	lua_pushvalue(L, 1); // this pushes the query
	lua_pushcclosure(L, query_capture_iter, 2);
	return 1;
}

static const struct luaL_Reg ts_funcs[] = {
	{ "load", ts_load },
	{ NULL, NULL }
};

static const struct luaL_Reg parser_methods[] = {
	{ "parse_string", parser_parse_string },
	{ "query", parser_query },
	{ "__gc", parser_gc },
	{ NULL, NULL }
};

static const struct luaL_Reg tree_methods[] = {
	{ "root", tree_root },
	{ "__gc", tree_gc },
	{ NULL, NULL }
};

static const struct luaL_Reg node_methods[] = {
	{ "start_byte", node_start_byte },
	{ "end_byte", node_end_byte },
	{ "start_byte_offset", node_start_byte }, // this and one bellow it for compat only
	{ "end_byte_offset", node_end_byte },
	{ "type", node_type },
	{ "named_descendant_for_byte_range", node_named_descendant_for_byte_range },
	{ NULL, NULL }
};

static const struct luaL_Reg query_methods[] = {
	{ "capture", query_capture },
	{ "__gc", query_gc },
	{ NULL, NULL }
};

int luaopen_ts(lua_State *L) {
	luaL_newmetatable(L, VIS_TS_PARSER); lua_pushvalue(L, -1); lua_setfield(L, -2, "__index"); luaL_setfuncs(L, parser_methods, 0);

	luaL_newmetatable(L, VIS_TS_TREE); lua_pushvalue(L, -1); lua_setfield(L, -2, "__index"); luaL_setfuncs(L, tree_methods, 0);

	luaL_newmetatable(L, VIS_TS_NODE); lua_pushvalue(L, -1); lua_setfield(L, -2, "__index"); luaL_setfuncs(L, node_methods, 0);

	luaL_newmetatable(L, VIS_TS_QUERY); lua_pushvalue(L, -1); lua_setfield(L, -2, "__index"); luaL_setfuncs(L, query_methods, 0);

	lua_newtable(L);
	luaL_setfuncs(L, ts_funcs, 0);
	return 1;
}
