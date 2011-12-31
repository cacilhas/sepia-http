LUA= lua
CP= install -m 0644 -o root -g admin
MD= mkdir -p

LUA_PREFIX= /opt/local
LUA_SUFFIX= /5.1
LUA_PATH= $(LUA_PREFIX)/share/lua$(LUA_SUFFIX)
LUA_CPATH= $(LUA_PREFIX)/lib/lua$(LUA_SUFFIX)

#-----------------------------------------------------------------------
test: $(TARGET)
	@LUA_CPATH="$(LUA_CPATH)/?.so;$(LUA_CPATH)/?.so;$(LUA_CPATH)/?/l?.so" LUA_PATH="$(LUA_PATH)/?.lua;src/?.lua;src/?/init.lua" $(LUA) tests/init.lua


install:
	$(MD) $(LUA_PATH)/sepia
	$(CP) src/sepia/* $(LUA_PATH)/sepia/
