local _M = {}

_M.version = "0.6.0"

local ac      = require("inc.load_ac")
local iputils = require("inc.resty.iputils")
local logger  = require("lib.log")

-- module-level cache of aho-corasick dictionary objects
local _ac_dicts = {}

-- module-level cache of cidr objects
local _cidr_cache = {}

function _M.equals(a, b)
	local equals, value

	if (type(a) == "table") then
		for _, v in ipairs(a) do
			equals, value = _M.equals(v, b)
			if (equals) then
				break
			end
		end
	else
		equals = a == b

		if (equals) then
			value = a
		end
	end

	return equals, value
end

function _M.greater(a, b)
	local greater, value

	if (type(a) == "table") then
		for _, v in ipairs(a) do
			greater, value = _M.greater(v, b)
			if (greater) then
				break
			end
		end
	else
		greater = a > b

		if (greater) then
			value = a
		end
	end

	return greater, value
end

function _M.regex_match(FW, subject, pattern)
	local opts = FW._pcre_flags
	local from, to, err, match, value

	if (type(subject) == "table") then
		for _, v in ipairs(subject) do
			match, value = _M.regex_match(FW, v, pattern)

			if (match) then
				break
			end
		end
	else
		from, to, err = ngx.re.find(subject, pattern, opts)

		if err then
			ngx.log(ngx.WARN, "error in regex_match: " .. err)
		end

		if from then
			match = true
			value = string.sub(subject, from, to)
		end
	end

	return match, value
end

function _M.ac_lookup(needle, haystack, ctx)
	local id = ctx.id
	local match, _ac, value

	-- dictionary creation is expensive, so we use the id of
	-- the rule as the key to cache the created dictionary
	if (not _ac_dicts[id]) then
		_ac = ac.create_ac(haystack)
		_ac_dicts[id] = _ac
	else
		_ac = _ac_dicts[id]
	end

	if (type(needle) == "table") then
		for _, v in ipairs(needle) do
			match, value = _M.ac_lookup(v, haystack, ctx)

			if (match) then
				break
			end
		end
	else
		match = ac.match(_ac, needle)

		if (match) then
			match = true
			value = needle
		end
	end

	return match, value
end

function _M.cidr_match(ip, cidr_pattern)
	local t = {}
	local n = 1

	if (type(cidr_pattern) ~= "table") then
		cidr_pattern = { cidr_pattern }
	end

	for _, v in ipairs(cidr_pattern) do
		-- try to grab the parsed cidr from out module cache
		local cidr = _cidr_cache[v]

		-- if it wasn't there, compute and cache the value
		if (not cidr) then
			local lower, upper = iputils.parse_cidr(v)
			cidr = { lower, upper }
			_cidr_cache[v] = cidr
		end

		t[n] = cidr
		n = n + 1
	end

	return iputils.ip_in_cidrs(ip, t), ip
end

return _M
