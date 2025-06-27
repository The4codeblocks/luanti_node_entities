
nodeentity = {}

local nodeentity = nodeentity

local usednames = core.get_mod_storage()
--[[ used to reset storage
usednames:from_table({})
--]]
local fs_context = {
	-- index by formname, playername
}

local nodeentities = {
	-- index by id
}

local registered = {

}

nodeentity.nodeentities = nodeentities
nodeentity.fs_context   = fs_context
nodeentity.registered   = registered

local veczero = vector.zero()

local create_detached_nodemeta = function(name, callbacks)
	local meta = ItemStack():get_meta()
	local inv = core.create_detached_inventory(name, callbacks)
	local detnmmt = table.copy(getmetatable(ItemStack():get_meta()))

	detnmmt.set_tool_capabilities = nil
	detnmmt.set_wear_bar_params = nil
	for k, v in pairs(detnmmt) do
		if v then
			detnmmt[k] = function(self, ...)
				return v(self.meta, ...)
			end
		end
	end
	detnmmt.mark_as_private = function()end
	detnmmt.get_inventory = function() return inv end

	local oldtotable = detnmmt.to_table
	detnmmt.to_table = function(self)
		local t = oldtotable(self)
		local lists = self:get_inventory():get_lists()
		for k, l in pairs(lists) do
			for i, v in ipairs(l) do
				l[i] = v:to_string()
			end
		end
		t.inventory = lists
		return t
	end

	local oldfromtable = detnmmt.from_table
	detnmmt.from_table = function(self, t)
		if not t then return end
		oldfromtable(self, t)
		local inv = self:get_inventory()
		for k, l in pairs(t.inventory) do
			for i, v in ipairs(l) do
				l[i] = ItemStack(v)
			end
			inv:set_size(k, #l)
		end
		inv:set_lists(t.inventory)
	end

	detnmmt.meta = meta
	return detnmmt
end

local create_detached_nodetimer = function()
	return {
		timeout = 0,
		elapsed = 0,
		tick = function(self, dt)
			if self.timeout > 0 then
				self.elapsed = self.elapsed + dt
				if self.elapsed > self.timeout then
					self.prevtimeout = self.timeout
					self.timeout = 0
					return true
				end
			end
			return false
		end,
		set = function(self, timeout, elapsed)
			self.timeout = timeout
			self.elapsed = elapsed
			return set
		end,
		start = function(self, timeout)
			self.timeout = timeout
			self.elapsed = 0
		end,
		stop = function(self)
			self.timeout = 0
		end,
		get_timeout = function(self)
			return self.timeout
		end,
		get_elapsed = function(self)
			return self.elapsed
		end,
		is_started = function(self)
			return self.timeout > 0
		end,
		abm = 0
	}
end

local find_nodeentity = function(pos)
	local relative = nodeentities[pos.relative]
	if not relative then return pos end
	local object = relative.object
	if not object:is_valid() then
		return nil
	end
	local parent, _, attachpos = object:get_attach()
	if parent then
		local eID = parent:get_luaentity()._attachments[("%04x|%04x|%04x"):format(pos.x + 32768, pos.y + 32768, pos.z + 32768)]
		local entity = nodeentities[eID]
		if entity and entity.object:is_valid() then
			return entity, {parent = parent, position = attachpos}
		else
			return parent:get_pos():offset(pos.x, pos.y, pos.z), {parent = parent, position = attachpos}
		end
	elseif pos == veczero then
		return relative
	else
		return object:get_pos():offset(pos.x, pos.y, pos.z)
	end
end

local oldgetmeta = core.get_meta
core.get_meta = function(pos)
	local nodeentitypos = find_nodeentity(pos)
	if nodeentitypos then
		if nodeentitypos.object then
			return nodeentitypos._metadata
		else
			return oldgetmeta(nodeentitypos)
		end
	end
end

local oldgetnode = core.get_node
core.get_node = function(pos)
	local nodeentitypos = find_nodeentity(pos)
	if nodeentitypos then
		if nodeentitypos.object then
			return nodeentitypos.object:get_properties().node
		else
			return oldgetnode(nodeentitypos)
		end
	end
	return {name = "ignore", param1 = 0, param2 = 0}
end

local oldgetnodeornil = core.get_node_or_nil
core.get_node_or_nil = function(pos)
	local nodeentitypos = find_nodeentity(pos)
	if nodeentitypos then
		if nodeentitypos.object then
			return nodeentitypos.object:get_properties().node
		else
			return oldgetnodeornil(nodeentitypos)
		end
	end
end

local oldswapnode = core.swap_node
core.swap_node = function(pos, node)
	local nodeentitypos, attachment = find_nodeentity(pos)
	if nodeentitypos then
		if nodeentitypos.object then
			local newentity = nodeentity.add(nodeentitypos.object:get_pos():offset(pos.x, pos.y, pos.z), node, true):get_luaentity()
			nodeentities[newentity._eID] = nil
			usednames:set_string(newentity._eID, "")
			newentity._metadata = nodeentitypos._metadata
			newentity._invname  = nodeentitypos._invname
			newentity._showfs   = nodeentitypos._showfs
			newentity._timer    = nodeentitypos._timer
			newentity._eID      = nodeentitypos._eID
			nodeentitypos.object:remove()
			nodeentities[newentity._eID] = newentity
			usednames:set_string(newentity._eID, "1")
			if attachment then newentity.object:set_attach(attachment.parent, "", vector.multiply(pos, 10)) end
		elseif attachment then
			local newnode = nodeentity.add(attachment.parent:get_pos():offset(pos.x, pos.y, pos.z), node)
			newnode:set_attach(attachment.parent, "", vector.multiply(pos, 10))
		else
			oldswapnode(nodeentitypos, node)
		end
	end
end

local oldsetnode = core.set_node
core.set_node = function(pos, node)
	local nodeentitypos, attachment = find_nodeentity(pos)
	if nodeentitypos then
		if nodeentitypos.object then
			local newentity = nodeentity.add(nodeentitypos.object:get_pos(), node)
			nodeentitypos.object:remove()
			if attachment then newentity:set_attach(attachment.parent, "", vector.multiply(pos, 10)) end
		elseif attachment then
			local newnode = nodeentity.add(attachment.parent:get_pos():offset(pos.x, pos.y, pos.z), node)
			newnode:set_attach(attachment.parent, "", vector.multiply(pos, 10))
		else
			oldsetnode(nodeentitypos, node)
		end
	end
end

local oldremovenode = core.remove_node
core.remove_node = function(pos)
	local nodeentitypos = find_nodeentity(pos)
	if nodeentitypos then
		if nodeentitypos.object then
			nodeentitypos.object:remove()
		else
			oldremovenode(nodeentitypos)
		end
	end
end

local oldhash = core.hash_node_position
core.hash_node_position = function(pos)
	if pos.relative then
		return ("%012x%s"):format(oldhash(pos), pos.relative)
	else
		return oldhash(pos)
	end
end

local uncommited = {}

local oldgetnodetimer = core.get_node_timer
core.get_node_timer = function(pos)
	local nodeentitypos = find_nodeentity(pos)
	if nodeentitypos then
		if nodeentitypos.object then
			return nodeentitypos._timer
		else
			return oldgetnodetimer(nodeentitypos)
		end
	end
end

local construct_relpos = function(entity)
	local _, _, pos = entity.object:get_attach()
	if pos then
		pos = pos * 0.1
	else
		pos = vector.zero()
	end
	pos.relative = entity._eID
	return pos
end

local oldunhash = core.get_position_from_hash
core.get_position_from_hash = function(hash)
	if type(hash) == "number" then
		return oldunhash(hash)
	else
		local pos = oldunhash(hash:sub(1, 12))
		pos.relative = hash:sub(13)
		return pos
	end
end

local convert_pos = function(pos)
	if pos.relative then
		local entity = nodeentities[pos.relative]
		if not entity then return end
		if entity.object:is_valid() then
			return entity.object:get_pos():offset(pos.x, pos.y, pos.z)
		end
	else
		return pos
	end
end

local oldsoundplay = core.sound_play
core.sound_play = function(spec, parameters, ephemeral)
	if not parameters.pos then return oldsoundplay(spec, parameters, ephermal) end
	local parameters = table.copy(parameters)
	local pos = parameters.pos
	local nodeentitypos = find_nodeentity(pos)
	if nodeentitypos then
		if nodeentitypos.object then
			parameters.pos = convert_pos(pos)
		else
			parameters.pos = pos
		end
		oldsoundplay(spec, parameters, ephermal)
	end
end

local oldinarea = vector.in_area
vector.in_area = function(pos, minp, maxp)
	return oldinarea(convert_pos(pos), vector.sort(convert_pos(minp), convert_pos(maxp)))
end

local olddirection = vector.direction
vector.direction = function(from, to)
	return olddirection(convert_pos(from), convert_pos(to))
end

local olddistance = vector.distance
vector.distance = function(from, to)
	return olddistance(convert_pos(pos), convert_pos(to))
end

local oldoffset = vector.offset
vector.offset = function(v, x, y, z)
	local newvec = oldoffset(v, x, y, z)
	newvec.relative = v.relative
	return newvec
end

local oldcopy = vector.copy
vector.copy = function(v)
	local newvec = oldcopy(v)
	newvec.relative = v.relative
	return newvec
end

local oldfloor = vector.floor
vector.floor = function(v)
	local newvec = oldfloor(v)
	newvec.relative = v.relative
	return newvec
end

local oldceil = vector.ceil
vector.ceil = function(v)
	local newvec = oldceil(v)
	newvec.relative = v.relative
	return newvec
end

local oldround = vector.round
vector.round = function(v)
	local newvec = oldround(v)
	newvec.relative = v.relative
	return newvec
end

local oldadd = vector.add
vector.add = function(a, b)
	local newvec = oldadd(a, b)
	newvec.relative = a.relative or ((type(b) == "table") and b.relative)
	return newvec
end

local oldsubtract = vector.subtract
vector.subtract = function(a, b)
	local newvec = oldsubtract(a, b)
	newvec.relative = a.relative
	return newvec
end

local vecmetatable = vector.metatable

oldmetaadd = vecmetatable.__add
vecmetatable.__add = function(a, b)
	local newvec = oldmetaadd(a, b)
	newvec.relative = a.relative or b.relative
	return newvec
end

oldmetasub = vecmetatable.__sub
vecmetatable.__sub = function(a, b)
	local newvec = oldmetasub(a, b)
	newvec.relative = a.relative
	return newvec
end

local oldshowformspec = core.show_formspec
local newshowformspec = function(entity)
	local invname = "[detached:"..entity._invname
	local meta = entity._metadata
	return function(playername, formname, formspec)
		while true do
			local i, j = formspec:find("%$%{.-%}")
			if not i then break end
			local key = formspec:sub(i + 2, j - 1)
			formspec = formspec:gsub("%$%{"..key.."%}", meta:get_string(key))
		end
		local oldinvname, _, relpos = entity.object:get_attach()
		if relpos then
			oldinvname = ("%%[nodemeta:%d,%d,%d"):format(relpos.x * 0.1, relpos.y * 0.1, relpos.z * 0.1)
		else
			oldinvname = "%[nodemeta:0,0,0"
		end
		formspec = formspec:gsub(oldinvname, invname):gsub("%[context", invname)
		fs_context[formname] = fs_context[formname] or {}
		fs_context[formname][playername] = {formspec, entity}
		entity._prevfs = formspec
		oldshowformspec(playername, formname, formspec)
	end
end

local parseformspec = function(formspec, entity)
	local invname = "[detached:"..entity._invname
	local meta = entity._metadata
	while true do
		local i, j = formspec:find("%$%{.-%}")
		if not i then break end
		local key = formspec:sub(i + 2, j - 1)
		formspec = formspec:gsub("%$%{"..key.."%}", meta:get_string(key))
	end
	return formspec:gsub("%[nodemeta:0,0,0", invname):gsub("%[context", invname)
end

local init_context = function(entity)
	core.show_formspec = newshowformspec(entity)
end
local fin_context = function()
	core.show_formspec = oldshowformspec
end

local t = core.registered_on_player_receive_fields
core.register_last_on_player_receive_fields = function(func)
	t[#t + 1] = func
	core.callback_origins[func] = {
		-- may be nil or return nil
		mod = core.get_current_modname and core.get_current_modname() or "??",
		name = debug.getinfo(1, "n").name or "??"
	}
end

core.register_last_on_player_receive_fields(function(player, formname, fields) -- ANTIPRIORITY
	local pname = player:get_player_name()
	if fs_context[formname] and fs_context[formname][pname] then
		fin_context()
		if fields.quit then fs_context[formname][pname] = nil end
	end
end)

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname:sub(0, 11) == "nodeentity:" then
		local data = formname:split(";", true, 1)
		local nodename = (data[1]):gsub("nodeentity:",""):gsub("__",":")
		local def = core.registered_nodes[nodename]
		local entity = nodeentities[data[2]]
		init_context(entity)
		def.on_receive_fields(construct_relpos(entity), formname, fields, player, entity)
		fin_context()
	end
end)

local abm_neighbors = {
	vector.new(-1,-1,-1),
	vector.new( 0,-1,-1),
	vector.new( 1,-1,-1),
	vector.new(-1, 0,-1),
	vector.new( 0, 0,-1),
	vector.new( 1, 0,-1),
	vector.new(-1, 1,-1),
	vector.new( 0, 1,-1),
	vector.new( 1, 1,-1),
	vector.new(-1,-1, 0),
	vector.new( 0,-1, 0),
	vector.new( 1,-1, 0),
	vector.new(-1, 0, 0),
	vector.new( 1, 0, 0),
	vector.new(-1, 1, 0),
	vector.new( 0, 1, 0),
	vector.new( 1, 1, 0),
	vector.new(-1,-1, 1),
	vector.new( 0,-1, 1),
	vector.new( 1,-1, 1),
	vector.new(-1, 0, 1),
	vector.new( 0, 0, 1),
	vector.new( 1, 0, 1),
	vector.new(-1, 1, 1),
	vector.new( 0, 1, 1),
	vector.new( 1, 1, 1),
}

local function check_neighbors(pos, include, exclude)
	local includeset = {}
	local excludeset = {}
	local igroups    = {}
	local egroups    = {}
	local icheck
	if include then
		for _, n in ipairs(include) do
			if n:sub(1,6) == "group:" then
				table.insert(igroups, n:sub(7))
			else
				includeset[n] = true
			end
		end
	else
		icheck = true
	end
	if exclude then
		for _, n in ipairs(exclude) do
			if n:sub(1,6) == "group:" then
				table.insert(egroups, n:sub(7))
			else
				excludeset[n] = true
			end
		end
	end
	for _, neighbor in ipairs(abm_neighbors) do
		local name = core.get_node(pos + neighbor).name
		if excludeset[name] then return false end
		if not icheck then
			if includeset[name] then icheck = true end
			for _, group in ipairs(igroups) do
				if core.get_item_group(name, group) then icheck = true end
			end
		end
		for _, group in ipairs(egroups) do
			if core.get_item_group(name, group) then return false end
		end
	end
	return icheck
end

local function register_nodeentity(nodename)
	if registered[nodename] then return core.log("Node entity for "..nodename.."already registered!") end

	local def = core.registered_nodes[nodename]
	if not def then return core.log("Node "..nodename.." doesn't exist!") end

	local entityname = "nodeentity:"..nodename:gsub(":","__")
	registered[nodename] = entityname

	local invcallbacks = function(entity)
		local relpos = construct_relpos(entity)
		return {
		allow_move = def.allow_metadata_inventory_move and function(inv, from_list, from_index, to_list, to_index, count, player)
			init_context(entity)
			local r = def.allow_metadata_inventory_move(relpos, from_list, from_index, to_list, to_index, count, player, entity)
			fin_context()
			return r
		end,

		allow_put = def.allow_metadata_inventory_put and function(inv, listname, index, stack, player)
			init_context(entity)
			local r = def.allow_metadata_inventory_put(relpos, listname, index, stack, player, entity)
			fin_context()
			return r
		end,

		allow_take = def.allow_metadata_inventory_take and function(inv, listname, index, stack, player)
			init_context(entity)
			local r = def.allow_metadata_inventory_take(relpos, listname, index, stack, player, entity)
			fin_context()
			return r
		end,
		
		on_move = def.on_metadata_inventory_move and function(inv, from_list, from_index, to_list, to_index, count, player)
			init_context(entity)
			def.on_metadata_inventory_move(relpos, from_list, from_index, to_list, to_index, count, player, entity)
			fin_context()
		end,

		on_put = def.on_metadata_inventory_put and function(inv, listname, index, stack, player)
			init_context(entity)
			def.on_metadata_inventory_put(relpos, listname, index, stack, player, entity)
			fin_context()
		end,

		on_take = def.on_metadata_inventory_take and function(inv, listname, index, stack, player)
			init_context(entity)
			def.on_metadata_inventory_take(relpos, listname, index, stack, player, entity)
			fin_context()
		end,
	} end

	local rclick

	if def.on_rightclick then
		rclick = function(self, clicker)
			init_context(self)
			def.on_rightclick(construct_relpos(self), self.object:get_properties().node, clicker, clicker:get_wielded_item(), {
				type = "node",
				under = self.object:get_pos(),
				above = nil
			}, entity)
			fin_context()
		end
	else
		rclick = function(self, clicker)
			local fs = self._metadata:get_string("formspec")
			self._showfs(clicker:get_player_name(), entityname..";"..self._eID, fs)
		end
	end

	local deactivate
	if def.on_destruct then
		if def.after_destruct then
			deactivate = function(self, removal)
				if self._NOELIM then return end
				init_context(self)
				if removal then
					def.on_destruct(construct_relpos(self), self)
					local node = self.object:get_properties().node
					nodeentities[self._eID] = nil
					usednames:set_string(self._eID, "")
					def.after_destruct(self.object:get_pos(), node, self)
				else
					self.NOREMOVE = true
				end
				fin_context()
			end
		else
			deactivate = function(self, removal)
				if self._NOELIM then return end
				init_context(self)
				if removal then
					def.on_destruct(construct_relpos(self), self)
					nodeentities[self._eID] = nil
					usednames:set_string(self._eID, "")
				else
					self.NOREMOVE = true
				end
				fin_context()
			end
		end
	elseif def.after_destruct then
		deactivate = function(self, removal)
			if self._NOELIM then return end
			init_context(self)
			if removal then
				local node = self.object:get_properties().node
				nodeentities[self._eID] = nil
				usednames:set_string(self._eID, "")
				def.after_destruct(self.object:get_pos(), node, self)
			else
				self.NOREMOVE = true
			end
			fin_context()
		end
	else
		deactivate = function(self, removal)
			if self._NOELIM then return end
			if removal then
				nodeentities[self._eID] = nil
				usednames:set_string(self._eID, "")
			else
				self.NOREMOVE = true
			end
		end
	end

	local death
	if def.after_dig_node then
		local death = function(self, killer)
			init_context(self)
			def.after_dig_node(self.object:get_pos(), self.object:get_properties().node, self._metadata, killer, self)
			fin_context()
		end
	end

	local punch
	if def.on_punch then
		if def.can_dig then
			punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir, damage)
				init_context(self)
				local relpos = construct_relpos(self)
				def.on_punch(relpos, self.object:get_properties().node, puncher, {
					type = "node",
					under = self.object:get_pos(),
					above = nil
				}, self)
				if not def.can_dig(relpos, puncher, self) then
					fin_context()
					return true
				end
				fin_context()
			end
		else
			punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir, damage)
				init_context(self)
				def.on_punch(construct_relpos(self), self.object:get_properties().node, puncher, {
					type = "node",
					under = self.object:get_pos(),
					above = nil
				}, self)
				fin_context()
			end
		end
	elseif def.can_dig then
		punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir, damage)
			init_context(self)
			if not def.can_dig(construct_relpos(self), puncher, self) then
				fin_context()
				return true
			end
			fin_context()
		end
	end

	local activate
	if def.on_construct then
		activate = function(self, staticdata, dtime_s)
			self._timer = create_detached_nodetimer()
			if staticdata and (staticdata ~= "") and (staticdata ~= "NOUPD") then
				local data = staticdata:split("|", true, 3)
				local eID = data[1]
				if nodeentities[eID] and nodeentities[eID].object:is_valid() then
					self._NOELIM = true
					self.object:remove()
				end
				nodeentities[eID] = self
				usednames:set_string(eID, "1")
				self._eID = eID
				local invname = "nodeentity"..eID
				self._invname = invname
				staticdata = data[4]
				self._timer:set(tonumber(data[2]), tonumber(data[3]))
				local metaref = create_detached_nodemeta(invname, invcallbacks(self))
				metaref:from_table(core.deserialize(staticdata:sub(5)))

				self.object:set_properties({
					node = {
						param1 = tonumber(staticdata:sub(1,2)),
						param2 = tonumber(staticdata:sub(3,4)),
						name = nodename
					}
				})

				self._metadata = metaref
				self._showfs = newshowformspec(self)
			else
				::makenameagain::
				local eID = ("%x%x"):format(math.random(16777216),math.random(16777216))
				if nodeentities[eID] or usednames:contains(eID) then goto makenameagain end
				nodeentities[eID] = self
				usednames:set_string(eID, "1")
				self._eID = eID
				local invname = "nodeentity"..eID
				self._invname = invname

				self.object:set_properties({
					node = {
						name = nodename,
						param1 = 240,
						param2 = def.place_param2,
					}
				})

				self._metadata = create_detached_nodemeta(invname, invcallbacks(self))
				self._showfs = newshowformspec(self)

				if staticdata ~= "NOUPD" then
					init_context(self)
					def.on_construct(construct_relpos(self), self)
					fin_context()
				end
			end
			local node = self.object:get_properties().node
			for _, lbm in ipairs(core.registered_lbms) do
				if not lbm.run_at_every_load then return end -- known flaw
				for _, name in ipairs(lbm.nodenames) do
					if (node.name == name) or ((name:sub(1,6) == "group:") and (core.get_item_group(node.name, name:sub(7)) ~= 0)) then
						lbm.action(construct_relpos(self), node, dtime_s, self)
						break
					end
				end
			end
		end
	else
		activate = function(self, staticdata, dtime_s)
			self._timer = create_detached_nodetimer()
			if staticdata and (staticdata ~= "") and (staticdata ~= "NOUPD") then
				local data = staticdata:split("|", true, 3)
				local eID = data[1]
				if nodeentities[eID] and nodeentities[eID].object:is_valid() then
					self._NOELIM = true
					self.object:remove()
				end
				nodeentities[eID] = self
				usednames:set_string(eID, "1")
				self._eID = eID
				local invname = "nodeentity"..eID
				self._invname = invname
				staticdata = data[4]
				self._timer:set(tonumber(data[2]), tonumber(data[3]))
				local metaref = create_detached_nodemeta(invname, invcallbacks(self))
				metaref:from_table(core.deserialize(staticdata:sub(5)))

				self.object:set_properties({
					node = {
						param1 = tonumber(staticdata:sub(1,2)),
						param2 = tonumber(staticdata:sub(3,4)),
						name = nodename
					}
				})

				self._metadata = metaref
				self._showfs = newshowformspec(self)
			else
				::makenameagain::
				local eID = ("%06x%06x"):format(math.random(16777216),math.random(16777216))
				if nodeentities[eID] or usednames:contains(eID) then goto makenameagain end
				nodeentities[eID] = self
				usednames:set_string(eID, "1")
				self._eID = eID
				local invname = "nodeentity"..eID
				self._invname = invname
				
				self.object:set_properties({
					node = {
						name = nodename,
						param1 = 240,
						param2 = def.place_param2,
					}
				})

				self._metadata = create_detached_nodemeta(invname, invcallbacks(self))
				self._showfs = newshowformspec(self)
			end
			local node = self.object:get_properties().node
			for _, lbm in ipairs(core.registered_lbms) do
				if not lbm.run_at_every_load then return end -- known flaw
				for _, name in ipairs(lbm.nodenames) do
					if (node.name == name) or ((name:sub(1,6) == "group:") and (core.get_item_group(node.name, name:sub(7)) ~= 0)) then
						lbm.action(construct_relpos(self), node, dtime_s, self)
						break
					end
				end
			end
		end
	end

	local step = function(self, dtime, moveresult)
		local pos = construct_relpos(self)
		local timer = self._timer
		if timer:tick(dtime) then
			if def.on_timer(pos, timer.prevtimeout, self) then
				timer:start(timer.prevtimeout)
			end
		end
		local fname = entityname..";"..self._eID
		local fs = self._metadata:get_string("formspec")
		local parsedfs = parseformspec(fs, self)
		if self._prevfs and (parsedfs ~= self._prevfs) then
			for pname, fsc in pairs(fs_context[fname] or {}) do
				self._showfs(pname, fname, fs)
			end
		end
		newtimerabm = timer.abm + dtime
		self.object:set_properties({infotext = self._metadata:get_string("infotext")})
		local node = self.object:get_properties().node
		for _, abm in ipairs(core.registered_abms) do
			if ((timer.abm % abm.interval) > (newtimerabm % abm.interval)) and (math.random(abm.chance) == 1) then
				for _, name in ipairs(abm.nodenames) do
					if (node.name == name) or ((name:sub(1,6) == "group:") and (core.get_item_group(node.name, name:sub(7)) ~= 0)) then
						if check_neighbors(pos, abm.neighbors, abm.without_neighbors) then
							abm.action(pos, node, 0, 0, self, dtime, moveresult) -- missing object counts
						end
						break
					end
				end
			end
		end
		timer.abm = newtimerabm
		if def._nodeentity_step then
			def._nodeentity_step(self, dtime, moveresult)
		end
	end

	local selbox
	if def.selection_box.type == "regular" then
		selbox = { -0.5, -0.5, -0.5, 0.5, 0.5, 0.5, rotate = true }
	elseif def.selection_box.fixed then
		selbox = def.selection_box.fixed
		if selbox then
			if type(selbox[1]) == "table" then selbox = selbox[1] end
		else
			selbox = (def.drawtype == "nodebox") and def.node_box
		end
		selbox = selbox and table.copy(selbox)
		selbox.rotate = true
	else
		selfbox = { -0.125, -0.125, -0.125, 0.125, 0.125, 0.125, rotate = true }
	end

	core.register_entity(":"..entityname, {
		initial_properties = {

			physical = def.walkable or (def.walkable == nil),
			-- Collide with `walkable` nodes.

			collide_with_objects = def.walkable or (def.walkable == nil),
			-- Collide with other objects if physical = true

			collisionbox = def.collision_box or (def.drawtype == "nodebox" and def.node_box),
			selectionbox = selbox,
			-- { xmin, ymin, zmin, xmax, ymax, zmax } in nodes from object position.
			-- Collision boxes cannot rotate, setting `rotate = true` on it has no effect.
			-- If not set, the selection box copies the collision box, and will also not rotate.
			-- If `rotate = false`, the selection box will not rotate with the object itself, remaining fixed to the axes.
			-- If `rotate = true`, it will match the object's rotation and any attachment rotations.
			-- Raycasts use the selection box and object's rotation, but do *not* obey attachment rotations.
			-- For server-side raycasts to work correctly,
			-- the selection box should extend at most 5 units in each direction.


			pointable = def.pointable or (def.pointable == nil),
			-- Can be `true` if it is pointable, `false` if it can be pointed through,
			-- or `"blocking"` if it is pointable but not selectable.
			-- Clients older than 5.9.0 interpret `pointable = "blocking"` as `pointable = true`.
			-- Can be overridden by the `pointabilities` of the held item.

			visual = "node",

			node = {name = nodename, param1=0, param2=0},
			-- Node to show when using the "node" visual

			makes_footstep_sound = true,
			-- If true, object is able to make footstep sounds of nodes
			-- (see node sound definition for details).

			damage_texture_modifier = "^[brighten",
			-- Texture modifier to be applied for a short duration when object is hit

			glow = def.light_source,
		},

		_nodename = nodename,

		on_activate = activate,
		on_deactivate = deactivate,
		on_step = step,
		on_punch = punch,
		on_death = death,
		on_rightclick = rclick,
		--[[
		on_attach_child = function(self, child) end,
		on_detach_child = function(self, child) end,
		on_detach = function(self, parent) end,
		]]
		get_staticdata = function(self)
			local properties = self.object:get_properties()
			local node = properties.node
			local timer = self._timer
			return string.format("%s|%f|%f|%02x%02x%s", self._eID, timer.timeout, timer.elapsed, node.param1, node.param2, (self._metadata and core.serialize(self._metadata:to_table())) or "")
		end,
	})

	return entityname
end

local nodesetname = "nodeentity:nodeset"

core.register_entity(nodesetname, {
	
	initial_properties = {

		visual =  "upright_sprite",
		textures = {"blank.png", "blank.png"},

		shaded = false,

		static_save = true,
		-- If false, never save this object statically. It will simply be
		-- deleted when the block gets unloaded.
		-- The get_staticdata() callback is never called then.
		-- Defaults to 'true'.
	},
	-- A table of object properties, see the `Object properties` section.
	-- The properties in this table are applied to the object
	-- once when it is spawned.

	-- Refer to the "Registered entities" section for explanations
	on_activate = function(self, staticdata, dtime_s)
		if staticdata and staticdata ~= "" then
			self._attachments = core.deserialize(staticdata)
		else
			self._attachments = {}
		end
	end,
	on_step = function(self, dtime, moveresult)
		if not self._attachments then return end
		for pos, eID in pairs(self._attachments) do
			local child = nodeentities[eID]
			if child and child.object:is_valid() then
				local listpos = pos:split("|")
				child.object:set_attach(self.object, "", 10 * vector.new(tonumber(listpos[1], 16) - 32768, tonumber(listpos[2], 16) - 32768, tonumber(listpos[3], 16) - 32768))
			end
		end
	end,
	on_attach_child = function(self, child)
		local _, _, attachpos = child:get_attach()
		local entity = child:get_luaentity()
		self._attachments[("%04x|%04x|%04x"):format(attachpos.x * 0.1 + 32768, attachpos.y * 0.1 + 32768, attachpos.z * 0.1 + 32768)] = entity._eID
	end,
	on_detach_child = function(self, child)
		if true then return end
		local entity = child:get_luaentity()
		if entity.NOREMOVE then return end
		local _, _, attachpos = child:get_attach()
		self._attachments[("%04x|%04x|%04x"):format(attachpos.x * 0.1 + 32768, attachpos.y * 0.1 + 32768, attachpos.z * 0.1 + 32768)] = nil
	end,
	get_staticdata = function(self)
		return core.serialize(self._attachments)
	end,
})

local function add_nodeentity(pos, node, noupdate)
	if not registered[node.name] then register_nodeentity(node.name) end
	local ref = core.add_entity(pos, registered[node.name], noupdate and "NOUPD")
	ref:set_properties({node = node})
	return ref
end

nodeentity.register = register_nodeentity
nodeentity.add = add_nodeentity

core.register_on_mods_loaded(function()
	core.register_on_player_receive_fields(function(player, formname, fields)
		local pname = player:get_player_name()
		if fs_context[formname] and fs_context[formname][pname] then
			init_context(fs_context[formname][pname][2])
		end
	end)

	local oldisprotected = core.is_protected
	core.is_protected = function(pos, player)
		if pos.relative then
			local entity = nodeentities[pos.relative]
			if not entity then return end
			if entity.object:is_valid() then
				return oldisprotected(entity.object:get_pos():offset(pos.x, pos.y, pos.z), player)
			end
		else
			return oldisprotected(pos, player)
		end
	end

	core.after(0, function()

	local vmanipmeta = getmetatable(VoxelManip())

	local oldvmget = vmanipmeta.get_node_at
	vmanipmeta.get_node_at = function(self, pos)
		local nodeentitypos = find_nodeentity(pos)
		if nodeentitypos then
			if nodeentitypos.object then
				return nodeentitypos.object:get_properties().node
			else
				return oldvmget(self, nodeentitypos)
			end
		end
		return {name = "ignore", param1 = 0, param2 = 0}
	end

	local oldvmset = vmanipmeta.set_node_at
	vmanipmeta.set_node_at = function(self, pos, node)
		local nodeentitypos, attachment = find_nodeentity(pos)
		if nodeentitypos then
			if nodeentitypos.object then
				uncommited[self] = uncommited[self] or {}
				uncommited[self][core.hash_node_position(pos)] = function()
					local newentity = nodeentity.add(nodeentitypos.object:get_pos(), node, true):get_luaentity()
					nodeentities[newentity._eID] = nil
					usednames:set_string(newentity._eID, "")
					newentity._metadata = nodeentitypos._metadata
					newentity._invname  = nodeentitypos._invname
					newentity._showfs   = nodeentitypos._showfs
					newentity._timer    = nodeentitypos._timer
					newentity._eID      = nodeentitypos._eID
					nodeentitypos.object:remove()
					nodeentities[newentity._eID] = newentity
					usednames:set_string(newentity._eID, "1")
					if attachment then newentity.object:set_attach(attachment.parent, "", vector.multiply(pos, 10)) end
				end
			elseif attachment then
				uncommited[self] = uncommited[self] or {}
				uncommited[self][core.hash_node_position(pos)] = function()
					local newnode = nodeentity.add(attachment.parent:get_pos():offset(pos.x, pos.y, pos.z), node, true)
					newnode:set_attach(attachment.parent, "", vector.multiply(pos, 10))
				end
			else
				oldvmset(self, nodeentitypos, node)
			end
		end
	end

	local oldvmwrite = vmanipmeta.write_to_map
	vmanipmeta.write_to_map = function(self, light)
		oldvmwrite(self, light)
		if not uncommited[self] then return end
		for k, v in pairs(uncommited[self]) do v() end
	end

	end)
end)

function nodeentity.read_world(pos, anchor, minp, maxp)
	assert(not minp.relative,   "nononono I don't want to make custom entity spaces (try ObjectRef:set_attach)")
	assert(not maxp.relative,   "nononono I don't want to make custom entity spaces (try ObjectRef:set_attach)")
	assert(not anchor.relative, "nononono I don't want to make custom entity spaces (try ObjectRef:set_attach)")
	assert(not maxp.relative,   "nononono I don't want to make custom entity spaces (try ObjectRef:set_attach)")
	local vm = VoxelManip(minp, maxp)
	local nodeset = core.add_entity(pos, nodesetname)
	for x = minp.x, maxp.x do
	for y = minp.y, maxp.y do
	for z = minp.z, maxp.z do
		local nodepos = vector.new(x, y, z)
		local node = vm:get_node_at(nodepos)
		if (node.name ~= "air") and (node.name ~= "ignore") then
			local newobject = add_nodeentity(pos, node)
			local newentity = newobject:get_luaentity()
			newentity._metadata:from_table(oldgetmeta(nodepos):to_table())
			newentity._showfs = newshowformspec(newentity)
			newobject:set_attach(nodeset, "", (nodepos - anchor) * 10)
		end
	end end end
	return nodeset
end
