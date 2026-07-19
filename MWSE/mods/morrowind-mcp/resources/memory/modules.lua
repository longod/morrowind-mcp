-- Static Memory module factories registered at startup.
-- Modules that represent many in-game instances manage their own dynamic entries internally.
return {
    require("morrowind-mcp.resources.memory.index"),
    require("morrowind-mcp.resources.memory.player"),
    require("morrowind-mcp.resources.memory.journal"),
    require("morrowind-mcp.resources.memory.quest"),
    require("morrowind-mcp.resources.memory.actor"),
}
