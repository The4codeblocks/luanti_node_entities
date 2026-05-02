
-- shared

local nodeentity = nodeentity
local entityname = nodeentity.entityname
local nodesetname = nodeentity.nodesetname
local find_nodeentity = nodeentity.get

local utils = nodeentity.utils
local csvify_pos = utils.pos_to_csv
local uncsvify_pos = utils.csv_to_pos


-- shared: any mod with deferred forms

local adapt_formgen = function(namespace, field, pos_argi, formspec_reti)
	local old = namespace[field]
	namespace[field] = function(...)
		local retvals = {old(...)}
		local formspec = retvals[formspec_reti]
		local pos = ({...})[pos_argi]
		local new_invpos = csvify_pos(pos)
		local old_invpos = csvify_pos(vector.new(pos.x, pos.y, pos.z))
		retvals[formspec_reti] = formspec:gsub(old_invpos:gsub("%@", "%%%@"):gsub("%-", "%%%-"), new_invpos)
		return unpack(retvals)
	end
end

-- default: chests.lua

if core.global_exists("default") then
	adapt_formgen(default.chest, "get_chest_formspec", 1, 1)
end

