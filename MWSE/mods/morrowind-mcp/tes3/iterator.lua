local jsonrpc = require("morrowind-mcp.server.jsonrpc")

local this = {}
--- TODO move to other helper
---@param list tes3referenceList
---@return fun(): tes3reference
function this.ForEachReferenceList(list)
    local function iterator()
        local ref = list.head

        if list.size ~= 0 then
            coroutine.yield(ref)
        end

        while ref.nextNode do
            ref = ref.nextNode
            coroutine.yield(ref)
        end
    end
    return coroutine.wrap(iterator)
end

--- This is a generic iterator function that is used
--- to loop over all the items in an inventory
---@param inventory tes3inventory|tes3itemStack[]
---@return fun(): tes3item, integer, tes3itemData|nil
function this.ForEachInventory(inventory)
    local function iterator()
        local items = inventory.items or inventory
        local itemCount = table.size(items)
        for i = 1, itemCount do -- expects stable iteration order
            local stack = items[i]
            if stack then
                local item = stack.object
                -- Skip uncarryable lights. They are hidden from the interface. A MWSE mod
                -- could make the player glow from transferring such lights, which the player
                -- can't remove. Some creatures like atronaches have uncarryable lights
                -- in their inventory to make them glow that are not supposed to be looted.
                if item and item.canCarry ~= false then
                    -- Account for restocking items,
                    -- since their count is negative.
                    local count = math.abs(stack.count)

                    -- First yield stacks with custom data
                    if stack.variables then
                        local variableCount = table.size(stack.variables)
                        for j = 1, variableCount do
                            local data = stack.variables[j]
                            if data then
                                coroutine.yield(item, data.count, data)
                                count = count - data.count
                            end
                        end
                    end

                    -- Then yield all the remaining copies
                    if count > 0 then
                        coroutine.yield(item, count)
                    end
                end
            end
        end
    end
    return coroutine.wrap(iterator)
end

-- TODO
-- function this.ForEachReferenceListObject(list, func)
-- end

-- function this.ForEachInventoryObject(inventory, func)
-- end

---@param i any[]
---@param func (fun(i: any, o : MCP.AnyMap?): MCP.AnyMap?)|(fun(i: any): MCP.AnyMap?)
---@param o MCP.AnyMap[]|nil
---@return MCP.AnyMap[]|nil
function this.ForEachObject(i, func, o)
    if not i then
        return nil
    end
    o = o or jsonrpc.array(table.size(i))
    for _, value in ipairs(i) do
        if func then
            local c = func(value)
            if c then
                table.insert(o, c)
            end
        end
    end
    if table.size(o) == 0 then
        return nil
    end
    return o
end


return this
