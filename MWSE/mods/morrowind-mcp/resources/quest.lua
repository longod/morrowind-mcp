local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local obj = require("morrowind-mcp.tes3.object")

local this = {}

---@param quest tes3quest
---@param isStarted boolean
---@param isActive boolean
---@param isFinished boolean
---@return boolean
local function Fileter(quest, isStarted, isActive, isFinished)
    if isStarted ~= nil and quest.isStarted ~= isStarted then
        return false
    end
    if isActive ~= nil and quest.isActive ~= isActive then
        return false
    end
    if isFinished ~= nil and quest.isFinished ~= isFinished then
        return false
    end
    return true
end


---@param isStarted boolean?
---@param isActive boolean?
---@param isFinished boolean?
---@return MCP.AnyMap[]?
function this.FindQuests(isStarted, isActive, isFinished)
    if tes3.onMainMenu() then
        return nil
    end

    if not tes3.worldController then
        return nil
    end

    local quests = tes3.worldController.quests
    if not quests then
        return nil
    end
    local array = jsonrpc.array(table.size(quests))
    for _, quest in ipairs(quests) do
        if quest:isValid() then
            if Fileter(quest, isStarted, isActive, isFinished) then
                local o = obj.tes3quest(quest)
                if o then
                    table.insert(array, o)
                end
            end
        end
    end
    return array
end

---@param desc MCP.Resource
---@return MCP.ResourceContent[]
function this:ContentHandler(desc)
    local entries = self.FindQuests(nil, true, nil) -- TODO getting flags
    local content = jsonrpc.TextResourceContents(desc.uri, json.encode(entries, { indent = false }), desc.mimeType)
    return { content }
end

return this
