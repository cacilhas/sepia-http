module(..., package.seeall)

_AUTHOR = "Rodrigo Cacilhas <batalema@cacilhas.info>"
_COPYRIGHT = "GNU/GPL 2011-2012 (c) " .. _AUTHOR
_DESCRIPTION = "Reimplementation of LuaPage for Sepia HTTP"
_NAME = "Sepia LuaPage"
_PACKAGE = "sepia.luapage"


local function lp_loadstring(s, request, response)
	local aux = s:gsub("<%?lua%s(.-)%?>", "]===] %1 lp_response = lp_response .. [===[")
	aux = aux:gsub("<%?lua=(.-)%?>", "]===] .. tostring(%1) .. [===[")

	local resp = [[
		local args = {...}
		local request = args[1]
		local response = args[2]
		local lp_response = [===[
	]] .. aux .. "]===] return lp_response"

	return assert(_G.loadstring(resp))(request, response)
end


loadstring = lp_loadstring


function loadfile(f, request, response)
	fd = io.input(f)
	local s = fd:read "*a"
	fd:close()
	return lp_loadstring(s, request, response)
end
