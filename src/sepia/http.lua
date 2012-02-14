require "sepia.luapage"
require "sss"
module(..., package.seeall)

_AUTHOR = "Rodrigo Cacilhas <batalema@cacilhas.info>"
_COPYRIGHT = "GNU/GPL 2011-2012 (c) " .. _AUTHOR
_DESCRIPTION = "HTTP support for Sepia latimanus"
_NAME = "Sepia HTTP"
_PACKAGE = "sepia.http"


http404 = [[<?xml version="1.0"?>
<!DOCTYPE html
	PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
	"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html>
	<head>
		<title>400 Not Found</title>
	</head>
	<body>
		<h1>Not Found</h1>
	</body>
</html>
]]


http500 = [[<?xml version="1.0"?>
<!DOCTYPE html
	PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
	"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html>
	<head>
		<title>500 Internal Server Error</title>
	</head>
	<body>
		<h1>Internal Server Error</h1>
	</body>
</html>
]]

indices = {
	"index.lp", "index.lc", "index.lua", "index.htm", "index.html"
}


------------------------------------------------------------------------
--                           Funções locais                           --
------------------------------------------------------------------------


local function seterror(response, status, page, err)

	sepia.log.debug("going out with status " .. status)
	if err then
		sepia.log.error(err)
	end

	response.status = status
	response.header = {
		["Content-Type"] = "text/html",
		["Content-Length"] = page:len(),
	}
	response.data = { page }

end


local anything2printable
anything2printable = function (e)

	if type(e) == "nil" then
		return ""

	elseif type(e) == "string" or type(e) == "number" then
		return e

	elseif type(e) == "table" then
		local resp = ""
		table.foreachi(e, function (i, e_)
			resp = resp .. anything2printable(e_)
		end)
		return resp

	elseif type(e) == "function" then
		return anything2printable(e())

	elseif type(e) == "thread" then
		local resp = ""
		local k, v = coroutine.resume(e)
		while k do
			if type(v) ~= "nil" then
				resp = resp .. anything2printable(e)
			end
			k, v = coroutine.resume(e)
		end
		return resp

	else
		return tostring(e)
	end

end


local function CookiesRFC2109(skt, name, data)
	local header = "Set-Cookie: "
		.. name .. "=" .. data.value:urlize()

	-- Comment
	if data.Comment then
		header = header .. "; Comment=" .. data.Comment
	end

	-- Domain
	if data.Domain then
		header = header .. "; Domain=" .. data.Domain
	end

	-- Max-Age (default: 5 minutos)
	if not data["Max-Age"] then data["Max-Age"] = 300 end
	header = header .. "; Max-Age=" .. data["Max-Age"]

	-- Path
	if data.Path then
		header = header .. "; Path=" .. data.Path
	end

	-- Secure
	if data.Secure then
		header = header .. "; Secure"
	end

	-- Version (default: 1)
	if not data.Version then data.Version = 1 end
	header = header .. "; Version=" .. data.Version

	skt:sendln(header)
end


local function CookiesRFC2965(skt, name, data)
	local header = "Set-Cookie2: "
		.. name .. "=" .. data.value:urlize()

	-- Comment
	if data.Comment then
		header = header .. "; Comment=" .. data.Comment
	end

	-- CommentURL
	if data.CommentURL then
		header = header
			.. '; CommentURL="' .. data.CommentURL .. '"'
	end

	-- Discard
	if data.Discard then
		header = header .. "; Discard"
	end

	-- Domain
	if data.Domain then
		header = header .. "; Domain=" .. data.Domain
	end

	-- Max-Age (default: 5 minutos)
	if not data["Max-Age"] then data["Max-Age"] = 300 end
	header = header .. "; Max-Age=" .. data["Max-Age"]

	-- Path
	if data.Path then
		header = header .. "; Path=" .. data.Path
	end

	-- Port
	if data.Port and #(data.Port) > 0 then
		header = header
			.. "; Port=" .. (","):join(data.Port)
	end

	-- Secure
	if data.Secure then
		header = header .. "; Secure"
	end

	-- Version (default: 1)
	if not data.Version then data.Version = 1 end
	header = header .. "; Version=" .. data.Version

	skt:sendln(header)
end


local function sendCookies(self, skt, client)
	client = client or ""
	table.foreach(self.raw, function (name, data) if data then
		data.value = tostring(anything2printable(data.value))
		if data.value:len() > 0 then
			if client:match "Mozilla" then
				-- Gecko implementa RFC 2109
				CookiesRFC2109(skt, name, data)
			else
				-- RFC 2965
				CookiesRFC2965(skt, name, data)
			end
		end
	end end)
end


-- Envia resposta
local function sendResponse(self)

	-- Envia cabeçalho
	self.skt:sendln("HTTP/1.1 " .. self.status)

	-- Envia headers
	table.foreach(self.header, function (k, v)
		if type(v) == "table" then
			table.foreach(v, function (i, e)
				self.skt:sendln(k:capwords() .. ": " .. anything2printable(e))
			end)
		else
			self.skt:sendln(k:capwords() .. ": " .. anything2printable(v))
		end
	end)

	-- Envia cookies
	--if not self.header["Cache-Control"] then
	--	self.skt:send('Cache-Control: no-cache="set-cookie2"')
	--end
	sendCookies(self.cookie, self.skt, self.client)

	self.skt:sendln ""

	if self.method ~= "HEAD" then
		-- Envia dados
		table.foreachi(self.data, function (i, e)
			if type(e) == "nil" then
				-- nil não envia nada
				sepia.log.debug("nil to send: nothing to do")
			elseif type(e) == "thread" then
				-- anything2printable não trata corrotinas corretamente ao
				-- enviar conteúdo
				local k, v = coroutine.resume(e)
				while k do
					if type(v) ~= "nil" then
						self.skt:send(anything2printable(v))
					end
					k, v = coroutine.resume(e)
				end
			else
				-- Em outros casos, anything2printable atende bem
				self.skt:send(anything2printable(e))
			end
		end)
	end

end


-- Trata cookies
local function processCookies(request)
	-- Cookies na requisição
	local cookies = {}
	local raw = request.header["Cookie"]

	if raw then
		if type(raw) ~= "table" then raw = { raw } end
		table.foreachi(raw, function (i, e) if type(e) == "string" then
			local data, name
			local cookie = {}

			for data in e:gmatch "([^;]+)" do
				table.foreach(data:deurlize(), function (key, value)
					key = key:trim()
					value = value:trim()
					if key:match "^%$" then
						cookie[key:sub(2)] = value
					else
						name = key
						cookie.value = value
					end
				end)
			end

			if name then cookies[name] = cookie end
		end end)
	end

	request.cookie = cookies

	-- Cookies na resposta
	local resp = { raw = {} }

	function resp:delete(name)
		if self ~= resp then error "use: cookie:delete(name)" end
		self.raw[name] = nil
	end

	function resp:get(name)
		if self ~= resp then error "use: cookie:get(name)" end
		if self.raw[name] then
			return self.raw[name].value
		else
			return nil
		end
	end

	function resp:set(name, value)
		if self ~= resp then error "use: cookie:set(name, value)" end
		if self.raw[name] then
			self.raw[name].value = value
		else
			self.raw[name] = { value = value }
		end
	end

	function resp:maxAge(name, value) if self.raw[name] then
		if value then
			self.raw[name]["Max-Age"] = value
		end
		return self.raw[name]["Max-Age"]
	end end

	function resp:comment(name, value) if self.raw[name] then
		if value then
			self.raw[name].Comment = value
		end
		return self.raw[name].Comment
	end end

	function resp:commentURL(name, value) if self.raw[name] then
		if value then
			self.raw[name].CommentURL = value
		end
		return self.raw[name].CommentURL
	end end

	function resp:discard(name, value) if self.raw[name] then
		if value then
			self.raw[name].Discard = value
		end
		return self.raw[name].Discard or false
	end end

	function resp:domain(name, value) if self.raw[name] then
		if value then
			self.raw[name].Domain = value
		end
		return self.raw[name].Domain
	end end

	function resp:path(name, value) if self.raw[name] then
		if value then
			self.raw[name].Path = value
		end
		return self.raw[name].Path
	end end

	function resp:port(name, value) if self.raw[name] then
		if value then
			value = 0 + value
			if type(self.raw[name].Port) == "table" then
				table.insert(self.raw[name].Port, value)
			else
				self.raw[name].Port = { value }
			end
		end
		return self.raw[name].Port
	end end

	function resp:secure(name, value) if self.raw[name] then
		if value then
			self.raw[name].Secure = value
		end
		return self.raw[name].Secure or false
	end end

	function resp:version(name, value) if self.raw[name] then
		if value then
			self.raw[name].Version = value
		end
		return self.raw[name].Version
	end end

	-- Carrega cookies recebidos para reenvio
	table.foreach(cookies, function (k, v) resp:set(k, v) end)

	return resp
end


-- Trata POST
local function processPost(request)
	local length = request.header["Content-Length"]
	if length then
		xpcall(
			function () length = 0 + length end,
			function (err) length = nil end
		)
	end

	if length == 0 then return end

	if request.header["Content-Type"]:match "^application/x%-www%-form%-urlencoded" then
		-- application/x-www-form-urlencoded

		local data
		if length then
			data = request.skt:rawrecv(length)
		else
			data = request.skt:receive()
		end

		if data then
			request[request.method] = data:deurlize()
		else
			request[request.method] = {}
		end

	elseif request.header["Content-Type"]:match "^multipart/form%-data" then
		-- multipart/form-data

		local boundary = request.header["Content-Type"]:match "boundary=(.+)"
		if not boundary then return end

		request[request.method] = {
			next = function ()
				local line = request.skt:receive()
				while (line and not line:match("^--" .. boundary .. "$")) do
					line = request.skt:receive()
				end
				if not line then return end

				line = request.skt:receive()
				local name = line:match 'name="(.+)"'
				local filename = line:match 'filename="(.+)"'
				local header = {}

				local line = skt:receive()
				while (line and line:len() > 0) do
					local key, value = line:match "^(.-):(.+)$"
					if key then
						header[key:trim()] = value and value:trim()
					end
					line = skt:receive()
				end

				local resp = {
					name = name,
					header = header,
				}
				if filename then
					local closed = false
					resp.filename = filename
					resp.readline = function ()
						if not closed then
							local line_ = skt:receive()
							if line_:match("^--" .. boundary .. "--") then
								closed = true
							else
								return line_
							end
						end
						return nil
					end
				else
					resp.value = skt:receive()
				end

				return resp
			end,
		}

	else
		-- Outros tipos
		request[request.method] = {
			readline = function ()
				return request.skt:receive()
			end,
		}
	end
end


-- Trata TRACE
local function processTrace(request, response)
	table.foreach(request.header, function (k, v)
		response.header[k] = v
	end)

	local length = request.header["Content-Length"]
	xpcall(
		function ()
			length = 0 + length
			if length > 0 then
				response.write(request.skt:recv(length))
			end
		end,
		function (err) length = 0 end
	)
end


-- Trata OPTIONS
local function processOptions(response)
	response.header["Content-Length"] = 0
	response.header["Content-Type"] = "text/plain"
	response.header["Compliance"] = {
		"rfc=2616;uncond",
		"rfc=2109, hdr=SetCookie",
		"rfc=2965, hdr=SetCookie-2",
	}
end


------------------------------------------------------------------------
-- 	  			         Funções de módulo                           --
------------------------------------------------------------------------


-- Funções pré-preparadas
prepared = {}


function process(skt)
	-- Processa o socket e retorna os objetos request e response

	local request = {}
	local commandline = skt:receive()

	if not commandline or commandline:len() == 0 then
		return nil, "no command line received"
	end

	local method, command, version = commandline:match "^(.-) (.-) ([^%s]+)"
	if not method then
		return nil, "command line does not match a HTTP format"
	end

	request.method = method
	request.command = command
	request.version = version:match "HTTP/(.+)"
	request.header = {}

	local line = skt:receive()
	while (line and line:len() > 0) do
		local key, value = line:match "^(.-):(.+)$"

		if key and value then
			key = key:trim():capwords()
			value = value:trim()
			if type(request.header[key]) == "table" then
				table.insert(request.header[key], value)
			elseif type(request.header[key]) == "nil" then
				request.header[key] = value
			else
				request.header[key] = { request.header[key], value }
			end
		end

		line = skt:receive()
	end

	-- Keep alive
	pcall(function () skt:timeout(0 + request.header["Keep-Alive"]) end)

	-- Socket para POST
	request.skt = skt

	local uri, data = command:match "^(.-)?(.+)$"
	if data then
		request.uri, request.GET = uri, data:deurlize()
	else
		request.uri, request.GET = command, {}
	end

	-- Amba as chaves uri e url referenciam a URI utilizada, mas uri
	-- armazena a string a ser usada para orientação da aplicação
	-- enquanto url mantém a URI original
	request.url = request.uri

	-- Obtém cookies
	xpcall(
		function () cookies = processCookies(request) end,
		function (err) cookies = {} end
	)

	-- Obtém dados de POST/PUT se conveniente (útil quando não é REST)
	if request.method == "POST" or request.method == "PUT" then
		pcall(processPost, request)
	end

	local response = {
		request = request,
		cookie = cookies,
		data = {},
		header = {
			["Content-Type"] = "text/html",
		},
		skt = skt,
		status = 200,

		write = function (self, data)
			table.insert(self.data, data)
		end,
	}

	return request, response

end

function prepare(generator, ...)
	-- Transforma uma aplicação HTTP, que recebe request e response, em
	-- uma aplicação Sepia, que recebe socket e endereço

	local args = { ... }
	return function (skt, addr)
		local keep_alive = true
		while keep_alive do
			keep_alive = false
			local request, response = process(skt)
			local method, client

			if type(request) == "table" then

				if request.header["Connection"] and
					request.header["Connection"]:lower() == "keep-alive"
				then
					keep_alive = true
					local tmout = skt:timeout()
					if tmout == 0 then skt:timeout(300) end
				end

				request.remote = addr
				method = request.method
				client = request.header["User-Agent"]

				if method == "OPTIONS" and request.command == "*" then
					processOptions(response)

				elseif method == "TRACE" then
					processTrace(request, response)

				else
					local f, err = generator(unpack(args))
					if f then
						xpcall(
							function () f(request, response) end,
							function (err) seterror(response, 500, http500, err) end
						)
					else
						seterror(response, 500, http500, err)
					end

					if not response.header.Date then
						response.header.Date = os.date "%a, %d %b %Y %H:%M:%S %Z"
					end

					if not response.header["Content-Length"] then
						local all_string = true
						local length = 0
						table.foreachi(response.data, function (i, e)
							if type(e) == "string" then
								length = length + e:len()
							else
								all_string = false
							end
						end)

						if all_string then
							response.header["Content-Length"] = length
						end
					end
				end

				if not response.header.Server then
					response.header.Server = "Sepia-HTTP"
				end
			end

			if type(response) == "table" then
				response.method = method
				response.client = client
				sendResponse(response)
			end
		end
	end
end


function httpapp(application)
	-- Retorna uma aplicação HTTP, capaz de receber os objetos request e
	-- response

	return function (request, response)
		xpcall(
			function ()
				application(request, response)
				response.header["Content-Type"] =
					response.header["Content-Type"] or "text/html"
			end,
			function (err) seterror(response, 500, http500, resp) end
		)
	end

end


function mediaroot(root)
	-- Retorna uma aplicação HTTP que lida com uma raiz de diretório
	-- contendo mídias diversas

	if os.execute("test -d " .. root) ~= 0 then
		local msg = root .. " is not a directory"
		sepia.log.error(msg)
		return nil, msg
	end
	if root:match "/$" then root = root:match "^(.-)/$" end

	return function (request, response)
		local path = root .. request.uri

		if os.execute("test -d " .. path) == 0 then
			-- Se a mídia for um diretório, procura o arquivo de índice
			if not path:match "/$" then path = path .. "/" end

			local index
			table.foreachi(indices, function (i, e)
				if os.execute("test -f " .. path .. e) == 0 then
					index = path .. e
				end
			end)
			path = index or path
		end

		if os.execute("test -f " .. path) == 0 then
			-- A mídia existe
			sepia.log.debug("requested media found: " .. path)

			if path:match "%.lua" or path:match "%.lc" then
				-- A mídia é um script Lua

				request.remote = addr
				local script, err = loadfile(path)

				if script then
					xpcall(
						function ()
							script(request, response)

							response.header["Content-Type"] =
								response.header["Content-Type"] or "text/html"

							if not response.header["Content-Length"] then
								local all_string = true
								local length = 0
								table.foreachi(response.data, function (i, e)
									if type(e) == "string" then
										length = length + e:len()
									else
										all_string = false
									end
								end)

								if all_string then
									response.header["Content-Length"] = length
								end
							end
						end,

						function (err) seterror(response, 500, http500, err) end
					)

				else
					-- Houve um erro na carga do script
					seterror(response, 500, http500, err)
				end

			elseif path:match "%.lp$" then
				-- A mídia é uma página Lua
				xpcall(
					function ()
						response:write(
							sepia.luapage.loadfile(path, request, response)
						)
					end,
					function (err) seterror(response, 500, http500, err) end
				)

			else
				-- A mídia não é executável

				-- Usa /etc/file/magic.mime para identificar o MIME
				local fd = io.popen("file -i " .. path)
				local aux = fd:read()
				fd:close()

				local mime
				if aux then mime = aux:match ": (.+)$" end
				mime = mime or "text/html"
				response.header["Content-Type"] = mime
				sepia.log.debug("media MIME type: " .. mime)

				xpcall(
					function ()
						local fd = io.input(path)

						response.header["Content-Length"] = fd:seek "end"
						-- TODO: suporte a reiniciar download quebrado
						fd:seek "set"
						response:write(coroutine.create(function ()
							aux = fd:read(1024)
							while aux do
								local b
								for b in aux:gmatch "." do
									coroutine.yield(b:byte())
								end
								aux = fd:read(1024)
							end
							fd:close()
						end))
					end,

					function (err) seterror(response, 500, http500, err) end
				)
			end

		else
			-- A mídia não existe
			seterror(response, 404, http404)
		end

	end

end


function multiapp(t)
	-- Retorna uma aplicação HTTP que redistribui a requisição para
	-- outras aplicações HTTP segundo uma tabela

	if type(t) ~= "table" then
		local msg = "no table supplied"
		sepia.log.error(msg)
		return nil, msg
	end

	return function (request, response)
		local app

		while not app do
			local key, uri
			if request.uri == "/" then
				key = "index"
			else
				key, uri = request.uri:match "^/(.-)(/.*)$"
				key = key or request.uri
				request.uri = uri or "/"
			end

			if type(t[key]) == "function" then
				app = t[key]

			elseif type(t[key]) ~= "table" or request.uri == "/" then
				seterror(response, 404, http404)
				return
			end
		end

		xpcall(
			function () app(request, response) end,
			function (err) seterror(response, 500, http500, err) end
		)
	end
end


function multihost(t)
	-- Retorna uma aplicação HTTP que redireciona a requisição para
	-- outras aplicações HTTP em uma tabela de acordo com o host

	if type(t) ~= "table" then
		local msg = "no table supplied"
		sepia.log.error(msg)
		return nil, msg
	end

	if not t.localhost then
		local msg = "table must contain localhost application"
		sepia.log.error(msg)
		return nil, msg
	end

	return function (request, response)
		local host = request.header["Host"]
		local app = t[host]

		if not app then
			host = host:match "^(.-):"
			if host then app = t[host] end
		end

		-- Aplicação por defeito é localhost
		app = app or t.localhost

		xpcall(
			function () app(request, response) end,
			function (err)seterror(response, 500, http500, err) end
		)
	end
end


function prepared.httpapp(application)
	return prepare(httpapp, application)
end


function prepared.mediaroot(root)
	return prepare(mediaroot, root)
end


function prepared.multiapp(t)
	return prepare(multiapp, t)
end


function prepared.multihost(t)
	return prepare(multihost, t)
end
