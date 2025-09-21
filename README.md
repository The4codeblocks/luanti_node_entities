# Node entity library (`nodeentity`)
Library for functional node entities, with minimal setup

## Namespace reference
```lua
nodeentity = {
  function add(pos, node, noupdate), -- creates a functional node entity at specified position in accordance to specified MapNode table (actually returns an ObjectRef)
  function read_world(pos, anchor, minp, maxp), -- creates a nodeset at <pos> with nodes from <minp> to <maxp> relative to <anchor>
  -- exposed internal tables
  nodeentities = {[entityID] = luaentity}, -- table of node entities, not guaranteed to be active
  fs_context = {
    [formname] = {
      [playername] = {formspec, entity} 
    }
  }, -- table of active forms in nodeentities
}
```

## Position format
```lua
local position = {
  x, y, z -- position components
  relative = entityID -- optional relativity specifier, makes the position relative to the specified node entity or its corresponding node entity set
}
```
These relative positions should work in most `core` namespace functions (library feature), if any of them don't work, make an issue

## Node entity sets (`"nodeentity:nodeset"`)
2 node entities *attached* to the same nodeset are able to access each-other with `core` namespace functions

To add a node entity to a node set, attach it as specified: `nodeobject:set_attach(nodeset, "", pos * 10)`, the engine requires the pos multiplication, but the automatic inclusion of the entity works as normal

## Node definition interface
```lua
local nodedef = {
  ...
  function _nodeentity_step(self, dtime, moveresult), -- runs exclusively on node entities, identical to <step> in entity defintions
  <other callbacks> -- current entity is appended to the end of function arguments (abms and lbms included)
  ...
}
```

## Entity fields
```lua
local entity = {
  ...
  function _showfs(playername, formname, formspec), -- used like core.show_formspec, includes the nuances in node forms
  _metadata, -- imitation of NodeMetaRef
  _invname, -- inventory name used in showing current node entity inventory
  _timer, -- lua implementation of NodeTimerRef
  _eID, -- current entity's persistent node entity ID
  ...
}
