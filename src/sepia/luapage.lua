module(..., package.seeall)

_AUTHOR = "Rodrigo Cacilhas <batalema@cacilhas.info>"
_COPYRIGHT = "GNU/GPL 2011-2012 (c) " .. _AUTHOR
_DESCRIPTION = "Reimplementation of LuaPage for Sepia HTTP"
_NAME = "Sepia LuaPage"
_PACKAGE = "sepia.luapage"


local function lp_loadstring(s, request, response)
		local resp = [[
				local args = {...}
				local request = args[1]
				local response = args[2]
				local lp_response = [===[
		]]
		local aux = s:gsub("<%?lua%s(.-)%?>", "]===] %1 lp_response = lp_response .. [===[")
		aux = aux:gsub("<%?lua=(.-)%?>", "]===] .. tostring(%1) .. [===[")
		resp = resp .. aux .. "]===] return lp_response"
		local f, err = _G.loadstring(resp)
		if f then
				return f(request, response)
		else
				return nil, err
		end
end


loadstring = lp_loadstring


function loadfile(f, request, response)
		local st, fd = pcall(io.input, f)
		if st then
				local s = fd:read "*a"
				fd:close()
				return lp_loadstring(s, request, response)
		else
				return nil, fd
		end
end
