local base = require("morrowind-mcp.core.itool")
local availability = require("morrowind-mcp.util.tes3_availability")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local ui_action = require("morrowind-mcp.util.ui_action")

---@class MCP.Tools.DialogueFetch: MCP.ITool
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.Tools.DialogueFetch
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Tools.DialogueFetch
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "dialogue_fetch" })
    instance.definition = jsonrpc.Tool({
        name = "dialogue-fetch",
        description =
        "Fetch the content of the current conversation with the actor you're talking to from the dialogue menu. Only the content of this conversation can be fetched. To access past conversations, read from the memory resource.",
        inputSchema = jsonrpc.InputSchema(
        ),
        outputSchema = jsonrpc.OutputSchema({
            actor = jsonrpc.JsonObjectSchema(),
            dialogues = jsonrpc.JsonArraySchema(),
            topics = jsonrpc.JsonArraySchema(),
            -- choices (1, 2, 3.. choices)
        }),
        annotations = jsonrpc.ToolAnnotations(nil, true, false)
    })
    return instance
end

function this:GetCapabilityConditions()
    return "Dialogue Menu must be displayed."
end

function this:CanExecute(arguments, context)
    -- TODO menu visibility availability by name, helper function.
    local ok, reason = availability.IsInGame()
    if not ok then
        return false, reason
    end
    return true
end

function this:Execute(arguments, context)

    -- local actor = tes3ui.getServiceActor()
    -- if not actor then
    --     local errorContent = jsonrpc.TextContent("No actor found. Please enter the dialogue menu.")
    --     return jsonrpc.CallToolResult(errorContent, nil, true)
    -- end

    -- tes3ui.findMenu(tes3ui.registerID("MenuDialog")):findChild(tes3ui.registerID("MenuDialog_topic_list"))

    -- menu handling or event accumulation

    -- MenuDialog_a_topic
    -- MenuDialog_persuasion
    -- MenuDialog_service_barter
    -- local topic = tes3ui.findMenu(tes3ui.registerID("MenuDialog")):findChild(tes3ui.registerID("MenuDialog_persuasion"))
    -- print(ui_action.BuildElementPath(topic))
    -- local message = tes3ui.findMenu(tes3ui.registerID("MenuDialog")):findChild(tes3ui.registerID("MenuDialog_hyper"))
    -- print(ui_action.BuildElementPath(message))
    -- local bye = tes3ui.findMenu(tes3ui.registerID("MenuDialog")):findChild(tes3ui.registerID("MenuDialog_button_bye"))
    -- print(ui_action.BuildElementPath(bye))

    -- "layout/MenuDialog/PartDragMenu_thick_border/PartDragMenu_center_frame/PartDragMenu_drag_frame/null/null/PartDragMenu_main/null/null/MenuDialog_topics_pane/PartScrollPane_outer_frame/PartScrollPane_pane/MenuDialog_persuasion"
    -- "layout/MenuDialog/PartDragMenu_thick_border/PartDragMenu_center_frame/PartDragMenu_drag_frame/null/null/PartDragMenu_main/null/MenuDialog_scroll_pane/PartScrollPane_outer_frame/PartScrollPane_pane/MenuDialog_hyper"
    -- "layout/MenuDialog/PartDragMenu_thick_border/PartDragMenu_center_frame/PartDragMenu_drag_frame/null/null/PartDragMenu_main/null/null/MenuDialog_button_bye"


    -- MenuDialog_header

    -- MenuDialog_hyper

    -- MenuDialog_notify
    -- MenuDialog_answer_block


    -- MenuDialog_disposition

    -- MenuDialog_button_bye

    return jsonrpc.CallToolResult(
        jsonrpc.TextContent("not yet implemented."),
        nil,
        true
    )
end

return this
