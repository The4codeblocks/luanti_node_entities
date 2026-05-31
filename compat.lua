
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

-- mesecons_mvps: init.lua

if core.global_exists("mesecon") then
	function mesecon.mvps_move_objects(pos, dir, nodestack, movefactor)
		local dir_k
		local dir_l
		for k, v in pairs(dir) do
			if v ~= 0 then
				dir_k = k
				dir_l = v
				break
			end
		end
		movefactor = movefactor or 1
		dir = vector.multiply(dir, movefactor)
		for id, obj in pairs(core.get_objects_inside_radius(pos, #nodestack + 1)) do
			local obj_pos = obj:get_pos()
			local cbox = obj:get_properties().collisionbox
			local min_pos = vector.add(obj_pos, vector.new(cbox[1], cbox[2], cbox[3]))
			local max_pos = vector.add(obj_pos, vector.new(cbox[4], cbox[5], cbox[6]))
			local ok = true
			for k, v in pairs(pos) do
				if ({x=1,y=1,z=1})[k] then
					local edge1, edge2
					if k ~= dir_k then
						edge1 = v - 0.51 -- More than 0.5 to move objects near to the stack.
						edge2 = v + 0.51
					else
						edge1 = v - 0.5 * dir_l
						edge2 = v + (#nodestack + 0.5 * movefactor) * dir_l
						-- Make sure, edge1 is bigger than edge2:
						if edge1 > edge2 then
							edge1, edge2 = edge2, edge1
						end
					end
					if min_pos[k] > edge2 or max_pos[k] < edge1 then
						ok = false
						break
					end
				end
			end
			if ok then
				local ent = obj:get_luaentity()
				if obj:is_player() or (ent and not mesecon.is_mvps_unmov(ent.name)) then
					local np = vector.add(obj_pos, dir)
					-- Move only if destination is not solid or object is inside stack:
					local nn = core.get_node(np)
					local node_def = core.registered_nodes[nn.name]
					local obj_offset = dir_l * (obj_pos[dir_k] - pos[dir_k])
					if (node_def and not node_def.walkable) or
							(obj_offset >= 0 and
									obj_offset <= #nodestack - 0.5) then
						obj:move_to(np)
					end
				end
			end
		end
	end
end

-- digilines: util.lua

if core.global_exists("digilines") then
	local oldgetnode = digilines.get_node_force
	function digilines.get_node_force(pos)
		if pos.relative then
			return core.get_node(pos)
		else
			return oldgetnode(pos)
		end
	end
	function digilines.addPosRule(p, r)
		return vector.add(p, r)
	end
	function digilines.cmpPos(p1, p2)
		return vector.equals(p1, p2)
	end
end

-- mesecons_luacontroller: init.lua

if core.get_modpath("mesecons_luacontroller") then
	local BASENAME = "mesecons_luacontroller:luacontroller"
	for a = 0, 1 do -- 0 = off  1 = on
		for b = 0, 1 do
			for c = 0, 1 do
				for d = 0, 1 do
					local cid = tostring(d)..tostring(c)..tostring(b)..tostring(a)
					local node_name = BASENAME..cid
					local old_on_construct = core.registered_nodes[node_name].on_construct
					core.override_item(node_name, {
						on_construct = function(pos)
							old_on_construct(pos)
						end
					})
				end
			end
		end
	end
end
