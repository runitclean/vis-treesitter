.POSIX:
# FIXME: very badly written, just to get stuff working, fix later

CFLAGS = -fPIC -Wall -O2 `pkg-config --cflags lua5.3 2>/dev/null || pkg-config --cflags lua`
LDFLAGS = -shared

DYNAMIC_LIBS = `pkg-config --libs tree-sitter`
STATIC_LIBS = -Wl,-Bstatic `pkg-config --libs tree-sitter` -Wl,-Bdynamic

LIBS = $(DYNAMIC_LIBS)

all:
	@$(MAKE) static || $(MAKE) dynamic

ts.so: ts.c
	$(CC) $(CFLAGS) -o $@ ts.c $(LDFLAGS) $(LIBS)

dynamic: clean
	$(MAKE) LIBS="$(DYNAMIC_LIBS)" ts.so

static: clean
	$(MAKE) LIBS="$(STATIC_LIBS)" ts.so

clean:
	rm -f ts.so

