# Node entity library (`nodeentity`)
## Namespace reference
```lua
nodeentity = {
  function register(nodename), -- registers a node entity in accordance to a defined node (does not update when definition changes), returns new entity name
  function add(pos, node, noupdate), -- creates a functional node entity at specified position in accordance to specified MapNode table (actually returns an ObjectRef)
  -- exposed internal tables
  nodeentities = {[entityID] = luaentity}, -- table of node entities, not guaranteed to be active
  fs_context = {
    [formname] = {
      [playername] = {formspec, entity} 
    }
  }, -- table of active forms in nodeentities
  registered = {[nodename] = entityname}, -- map from node names to entity names
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
