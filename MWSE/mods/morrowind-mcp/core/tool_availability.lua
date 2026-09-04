---@class MCP.ToolAvailabilityRelatedTool
---@field name string
---@field relationship string

---@class MCP.ToolAvailabilityRelatedResource
---@field uri MCP.ResourceUri
---@field relationship string

---@class MCP.ToolAvailabilityDetails
---@field unavailableBecause string
---@field availableWhen string
---@field relatedTools MCP.ToolAvailabilityRelatedTool[]?
---@field relatedResources MCP.ToolAvailabilityRelatedResource[]?

---@class MCP.ToolAvailability: MCP.ToolAvailabilityDetails
---@field reason MCP.ToolAvailabilityReason
---@field guidance string

local this = {}

---@enum MCP.ToolAvailabilityReason
local reason = {
    uninitialized = "uninitialized",
    not_in_game = "not_in_game",
    not_in_menu_mode = "not_in_menu_mode",
    paused_in_menu_mode = "paused_in_menu_mode",
    menu_unavailable = "menu_unavailable",
    character_generation_unfinished = "character_generation_unfinished",
    unsupported = "unsupported",
    -- specified reasons below
    input_binding_unavailable = "input_binding_unavailable",
    target_not_found = "target_not_found",
    movement_unavailable = "movement_unavailable",
    navigation_unavailable = "navigation_unavailable",
    no_active_navigation = "no_active_navigation",
    journal_unavailable = "journal_unavailable",
}

this.reason = reason

--- Render a consistent, declarative explanation for an unavailable tool.
---@param details MCP.ToolAvailabilityDetails
---@return string
function this.FormatGuidance(details)
    local guidance = "Unavailable because: " .. details.unavailableBecause ..
        "\nAvailable when: " .. details.availableWhen
    if details.relatedTools then
        for _, relatedTool in ipairs(details.relatedTools) do
            guidance = guidance .. "\nRelated tool: `" .. relatedTool.name .. "` " .. relatedTool.relationship
        end
    end
    if details.relatedResources then
        for _, relatedResource in ipairs(details.relatedResources) do
            guidance = guidance .. "\nRelated resource: `" .. relatedResource.uri .. "` " .. relatedResource.relationship
        end
    end
    return guidance
end

--- Create the structured explanation returned when a tool cannot run.
---@param reason MCP.ToolAvailabilityReason
---@param details MCP.ToolAvailabilityDetails
---@return MCP.ToolAvailability
function this.Unavailable(reason, details)
    local availability = {
        reason = reason,
        unavailableBecause = details.unavailableBecause,
        availableWhen = details.availableWhen,
        relatedTools = details.relatedTools,
        relatedResources = details.relatedResources,
    }
    availability.guidance = this.FormatGuidance(availability)
    return availability
end

--- Add tool-specific related tools to an existing availability result.
---@param availability MCP.ToolAvailability
---@param relatedTools MCP.ToolAvailabilityRelatedTool[]
---@return MCP.ToolAvailability
function this.WithRelatedTools(availability, relatedTools)
    return this.Unavailable(availability.reason, {
        unavailableBecause = availability.unavailableBecause,
        availableWhen = availability.availableWhen,
        relatedTools = relatedTools,
        relatedResources = availability.relatedResources,
    })
end

return this
