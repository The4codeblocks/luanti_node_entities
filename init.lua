
nodeentity = {}

local core = core
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

local entityname = "nodeentity:node"

nodeentity.nodeentities = nodeentities
nodeentity.fs_context   = fs_context
nodeentity.name         = entityname

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
		for k in pairs(inv:get_lists()) do
			inv:set_size(k, 0)
		end
		if t.inventory then
			for k, l in pairs(t.inventory) do
				for i, v in ipairs(l) do
					l[i] = ItemStack(v)
				end
				inv:set_size(k, #l)
			end
			inv:set_lists(t.inventory)
		end
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

local convert_pos = function(pos)
	if pos.relative then
		local entity = nodeentities[pos.relative]
		if not entity then return end
		if entity.object:is_valid() then
			return entity.object:get_pos() + vector.new(pos.x, pos.y, pos.z):rotate(entity.object:get_rotation())
		end
	else
		return pos
	end
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
			return parent:get_pos() + vector.new(pos.x, pos.y, pos.z):rotate(parent:get_rotation()), {parent = parent, position = attachpos}
		end
	elseif pos == veczero then
		return relative
	else
		return object:get_pos() + vector.new(pos.x, pos.y, pos.z):rotate(object:get_rotation())
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
			return nodeentitypos:get_node()
		else
			return oldgetnode(nodeentitypos)
		end
	end
	return {name = "air", param1 = 0, param2 = 0}
end

local oldgetnodeornil = core.get_node_or_nil
core.get_node_or_nil = function(pos)
	local nodeentitypos = find_nodeentity(pos)
	if nodeentitypos then
		if nodeentitypos.object then
			return nodeentitypos:get_node()
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
			nodeentitypos.object:set_properties({node = node})
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
			nodeentitypos.object:set_properties({node = node})
			nodeentitypos.metaref:from_table({})
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
		return ("%012x@%s"):format(oldhash(pos), pos.relative)
	else
		return oldhash(pos)
	end
end

local oldunhash = core.get_position_from_hash
core.get_position_from_hash = function(hash)
	if type(hash) == "number" then
		return oldunhash(hash)
	elseif hash:find("@") then
		local pos = oldunhash(hash:sub(1, 12))
		pos.relative = hash:sub(14)
		return pos
	else
		return oldunhash(hash)
	end
end

local oldPTS = core.pos_to_string
core.pos_to_string = function(pos, precision)
	local retval = oldPTS(pos)
	if pos.relative then
		retval = retval .. "@" .. pos.relative
	end
	return retval
end

local oldSTP = core.string_to_pos
core.string_to_pos = function(str)
	if not str then return end
	local separate = str:split("@", true, 1)
	local pos = oldSTP(separate[1])
	if not pos then return end
	pos.relative = separate[2]
	return pos
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
		pos = pos / 10
	else
		pos = vector.zero()
	end
	pos.relative = entity._eID
	return pos
end

local oldsoundplay = core.sound_play
core.sound_play = function(spec, parameters, ephemeral)
	if not parameters.pos then return oldsoundplay(spec, parameters, ephemeral) end
	local parameters = table.copy(parameters)
	local pos = parameters.pos
	local nodeentitypos = find_nodeentity(pos)
	if nodeentitypos then
		if nodeentitypos.object then
			parameters.pos = convert_pos(pos)
		else
			parameters.pos = pos
		end
		return oldsoundplay(spec, parameters, ephemeral)
	end
end

local oldinarea = vector.in_area
vector.in_area = function(pos, minp, maxp)
	return oldinarea(convert_pos(pos), vector.sort(convert_pos(minp), convert_pos(maxp)))
end

local oldrandinarea = vector.random_in_area
vector.random_in_area = function(minp, maxp)
	return oldrandinarea(vector.sort(convert_pos(minp), convert_pos(maxp)))
end

local oldVTS = vector.to_string
vector.to_string = function(pos)
	local retval = oldVTS(pos)
	if pos.relative then
		retval = retval .. "@" .. pos.relative
	end
	return retval
end

local oldSTV = vector.from_string
vector.from_string = function(str, init)
	if not str then return end
	local separate = str:split("@", true, 1)
	local pos = oldSTV(separate[1], init)
	if not pos then return nil end
	pos.relative = separate[2]
	return pos
end

local convert_func = function(location, key)
	local oldfunc = location[key]
	location[key] = function(a, ...)
		return oldfunc(convert_pos(a), ...)
	end
end

local convert_func2 = function(location, key)
	local oldfunc = location[key]
	location[key] = function(a, b, ...)
		local a = convert_pos(a)
		local b = convert_pos(b)
		return oldfunc(a, b, ...)
	end
end

local convert_method = function(location, key)
	local oldfunc = location[key]
	location[key] = function(self, a, ...)
		return oldfunc(self, convert_pos(a), ...)
	end
end

local convert_method2 = function(location, key)
	local oldfunc = location[key]
	location[key] = function(self, a, b, ...)
		return oldfunc(self, convert_pos(a), convert_pos(b), ...)
	end
end

local relativize_func = function(location, key)
	local oldfunc = location[key]
	location[key] = function(a, ...)
		local retval = oldfunc(a, ...)
		retval.relative = a.relative
		return retval
	end
end

local convert_field = function(location, key)
	if not location then return end
	if not location[key] then return end
	location[key] = convert_pos(location[key])
end

local oldaddparticle = core.add_particle
core.add_particle = function(def)
	def = table.copy(def)
	convert_field(def, "pos")
	oldaddparticle(def)
end

local oldaddparticlespawner = core.add_particlespawner
core.add_particlespawner = function(def)
	def = table.copy(def)
	convert_field(def, "minpos")
	convert_field(def, "maxpos")
	if type(def.pos) == "table" then
		if def.pos.x then
			convert_field(def, "pos")
		else
			convert_field(def.pos, "min")
			convert_field(def.pos, "max")
		end
	end
	if def.pos_tween then
		for k, v in ipairs(def.pos_tween) do
			if type(v) == "table" then
				if v.x then
					convert_field(def.pos_tween, k)
				else
					convert_field(v, "min")
					convert_field(v, "max")
				end
			end
		end
	end
	oldaddparticlespawner(def)
end

convert_func2(vector, "direction")
convert_func2(vector, "distance")
convert_func2(vector, "sort")

relativize_func(vector, "offset")
relativize_func(vector, "copy")
relativize_func(vector, "apply")
relativize_func(vector, "rotate_around_axis")
relativize_func(vector, "rotate")

convert_func2(core, "add_entity")

local oldnew = vector.new
vector.new = function(x, y, z, r)
	local newvec = oldnew(x, y, z)
	newvec.relative = r
	return newvec
end

local oldadd = vector.add
vector.add = function(a, b)
	local newvec = oldadd(a, b)
	newvec.relative = a.relative or ((type(b) == "table") and b.relative)
	return newvec
end

relativize_func(vector, "subtract")

local vecmetatable = vector.metatable

oldmetaadd = vecmetatable.__add
vecmetatable.__add = function(a, b)
	local newvec = oldmetaadd(a, b)
	newvec.relative = a.relative or b.relative
	return newvec
end

relativize_func(vecmetatable, "__sub")
relativize_func(vecmetatable, "__unm")

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
			oldinvname = ("%%[nodemeta:%d,%d,%d"):format(relpos.x/10, relpos.y/10, relpos.z/10)
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

local invcallbacks = function(entity)
	local relpos = construct_relpos(entity)
	local def = core.registered_nodes[entity:get_node().name]
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

local rclick = function(self, clicker)
	local def = core.registered_nodes[self:get_node().name]
	if def.on_rightclick then
		init_context(self)
		local retval = def.on_rightclick(construct_relpos(self), self:get_node(), clicker, clicker:get_wielded_item(), {
			type = "node",
			under = self.object:get_pos(),
			above = nil
		}, entity)
		fin_context()
		if retval then clicker:set_wielded_item(retval) end
	else
		local fs = self._metadata:get_string("formspec")
		self._showfs(clicker:get_player_name(), entityname..";"..self._eID, fs)
	end
end

local deactivate = function(self, removal)
	local def = core.registered_nodes[self:get_node().name]
	if self._NOELIM then return end
	init_context(self)
	local relpos = construct_relpos(self)
	if removal then
		if def.on_destruct then
			def.on_destruct(relpos, self)
		end
		nodeentities[self._eID] = nil
		usednames:set_string(self._eID, "")
		if def.after_destruct then
			local node = self:get_node()
			def.after_destruct(self.object:get_pos(), node, self)
		end
	else
		self._NOREMOVE = true
	end
	fin_context()
end

local death = function(self, killer)
	local def = core.registered_nodes[self:get_node().name]
	if def.after_dig_node then
		init_context(self)
		def.after_dig_node(convert_pos(construct_relpos(self)), self:get_node(), self._metadata, killer, self)
		fin_context()
	end
end

local punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir, damage)
	local def = core.registered_nodes[self:get_node().name]
	init_context(self)
	local relpos = construct_relpos(self)
	def.on_punch(relpos, self:get_node(), puncher, {
		type = "node",
		under = convert_pos(relpos),
		above = nil
	}, self)
	if def.can_dig then
		if def.can_dig(relpos, puncher, self) then
			core.node_dig(relpos, self:get_node(), puncher, self)
		else
			fin_context()
			return true
		end
	end
	fin_context()
end

local generate_eID = function()
	local eID
	repeat
		eID = ("%x%x"):format(math.random(16777216),math.random(16777216))
	until not (nodeentities[eID] or usednames:contains(eID))
	return eID
end

local eval_number = function(str, default)
	if str == "" then return default end
	return tonumber(str, 16)
end

local eval_string = function(str, default)
	if str == "" then return default end
	return str
end

local activate = function(self, staticdata, dtime_s)
	self._timer = create_detached_nodetimer()
	local data = {"", "", "", "", ""}
	if staticdata and (staticdata ~= "") then
		data = staticdata:split("|", true, 4)
	end
	local nodename = data[4]
	if nodename == "ignore" or nodename == "air" or nodename == "" then
		self._NOELIM = true
		return self.object:remove()
	end
	local eID = data[1]
	local init
	if eID == "" then
		eID = generate_eID()
		init = true
	end
	if nodeentities[eID] and nodeentities[eID].object:is_valid() then
		self._NOELIM = true
		return self.object:remove()
	end
	nodeentities[eID] = self
	usednames:set_string(eID, "1")
	self._eID = eID
	local invname = "nodeentity"..eID
	self._invname = invname
	local metaref = create_detached_nodemeta(invname, invcallbacks(self))
	self._metadata = metaref
	self._timer:set(tonumber(data[2]), tonumber(data[3]))
	
	staticdata = data[5]
	metaref:from_table(core.deserialize(staticdata:sub(5)) or {})
	local def = core.registered_nodes[nodename]
	self:set_node({
		param1 = eval_number(staticdata:sub(1,2), 240),
		param2 = eval_number(staticdata:sub(3,4), def.place_param2),
		name   = nodename
	})

	local relpos = construct_relpos(self)

	if def.on_construct then
		init_context(self)
		def.on_construct(relpos, self)
		fin_context()
	end

	self._showfs = newshowformspec(self)
	local node = self:get_node()
	for _, lbm in ipairs(core.registered_lbms) do
		if not lbm.run_at_every_load then return end -- known flaw
		for _, name in ipairs(lbm.nodenames) do
			if (node.name == name) or ((name:sub(1,6) == "group:") and (core.get_item_group(node.name, name:sub(7)) ~= 0)) then
				lbm.action(relpos, node, dtime_s, self)
				break
			end
		end
	end
end

local step = function(self, dtime, moveresult)
	local def = core.registered_nodes[self:get_node().name]
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
	local newtimerabm = timer.abm + dtime
	self.object:set_properties({infotext = self._metadata:get_string("infotext")})
	local node = self:get_node()
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

core.register_entity(entityname, {
	initial_properties = {

		visual = "node",
		-- Node to show when using the "node" visual

		makes_footstep_sound = true,
		-- If true, object is able to make footstep sounds of nodes
		-- (see node sound definition for details).

		damage_texture_modifier = "^[brighten",
		-- Texture modifier to be applied for a short duration when object is hit
	},

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
	get_node = function(self)
		return self.object:get_properties().node
	end,
	set_node = function(self, node)
		local def = core.registered_nodes[node.name]

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
			selbox = { -0.125, -0.125, -0.125, 0.125, 0.125, 0.125, rotate = true }
		end

		self.object:set_properties({
			node = node,
			selectionbox = selbox,
			glow = def.light_source,
			physical = def.walkable or (def.walkable == nil),
			pointable = def.pointable or (def.pointable == nil),
			collide_with_objects = def.walkable or (def.walkable == nil),
			collisionbox = def.collision_box or (def.drawtype == "nodebox" and def.node_box),
		})
	end,
	get_staticdata = function(self)
		local node = self:get_node()
		local timer = self._timer
		return string.format("%s|%f|%f|%s|%02x%02x%s", self._eID, timer.timeout, timer.elapsed, node.name, node.param1, node.param2, (self._metadata and core.serialize(self._metadata:to_table())) or "")
	end,
})

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
		if entity._NOREMOVE then return end
		local _, _, attachpos = child:get_attach()
		self._attachments[("%04x|%04x|%04x"):format(attachpos.x * 0.1 + 32768, attachpos.y * 0.1 + 32768, attachpos.z * 0.1 + 32768)] = nil
	end,
	get_staticdata = function(self)
		return core.serialize(self._attachments)
	end,
})

local function add_nodeentity(pos, node)
	if node.name == "ignore" or node.name == "air" then return end
	return core.add_entity(pos, entityname, "|0|0|"..node.name.."|")
end

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
				return nodeentitypos:get_node()
			end
			return oldvmget(self, nodeentitypos)
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
					nodeentitypos.object:set_properties({node = node})
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

	local dummy = core.add_entity(veczero, nodesetname)
	local objmeta = getmetatable(dummy)
	dummy:remove()

	convert_method(objmeta, "set_pos")
	convert_method(objmeta, "move_to")

	end)
end)

function nodeentity.read_world(pos, anchor, minp, maxp)
	local minp, maxp = vector.sort(convert_pos(minp), convert_pos(maxp))
	local pos = convert_pos(pos)
	local anchor = convert_pos(anchor)
	assert(pos, "can't read from the void")
	assert(anchor, "can't place in the void")
	local vm = VoxelManip(minp, maxp)
	local nodeset = core.add_entity(pos, nodesetname)
	local nodepos = vector.zero()
	for x = minp.x, maxp.x do
	for y = minp.y, maxp.y do
	for z = minp.z, maxp.z do
		nodepos.x, nodepos.y, nodepos.z = x, y, z
		local node = vm:get_node_at(nodepos)
		if (node.name ~= "air") and (node.name ~= "ignore") then
			local newobject = add_nodeentity(pos, node)
			local newentity = newobject:get_luaentity()
			newentity._metadata:from_table(oldgetmeta(nodepos):to_table())
			newobject:set_attach(nodeset, "", (nodepos - anchor) * 10)
		end
	end end end
	return nodeset
end
