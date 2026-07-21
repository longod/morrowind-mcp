local this = {}

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
    })

    local enumname = require("morrowind-mcp.tes3.enumname")

    unitwind:start("morrowind-mcp.tes3.enumname")

    unitwind:test("EnumName returns canonical name for non-bitflag enums", function()
        unitwind:expect(enumname.objectType(tes3.objectType.activator)).toBe("activator")
        unitwind:expect(enumname.dialogueType(tes3.dialogueType.service)).toBe("service")
    end)

    unitwind:test("BitFlagNames decodes actionFlag into multiple names", function()
        local combined = tes3.actionFlag.doorClosing + tes3.actionFlag.doorJammedClosing
        local names = enumname.actionFlag(combined)
        unitwind:expect(table.concat(names, "|")).toBe("doorClosing|doorJammedClosing")
    end)

    unitwind:test("BitFlagNames keeps zero-valued flag names", function()
        local names = enumname.animationStartFlag(tes3.animationStartFlag.normal)
        unitwind:expect(table.concat(names, "|")).toBe("normal")
    end)

    unitwind:test("BitFlagNames decodes merchantService and uiState combinations", function()
        local merchant = tes3.merchantService.spells + tes3.merchantService.repair
        local merchantNames = enumname.merchantService(merchant)
        unitwind:expect(table.concat(merchantNames, "|")).toBe("spells|repair")

        local ui = tes3.uiState.disabled + tes3.uiState.active
        local uiNames = enumname.uiState(ui)
        unitwind:expect(table.concat(uiNames, "|")).toBe("disabled|active")
    end)

    unitwind:test("EnumName returns nil for invalid value type", function()
        local name = enumname.objectType("activator") ---@diagnostic disable-line: param-type-mismatch
        unitwind:expect(name).toBe(nil)
    end)

    unitwind:test("EnumName returns nil for nil value", function()
        local name = enumname.objectType(nil) ---@diagnostic disable-line: param-type-mismatch
        unitwind:expect(name).toBe(nil)
    end)

    unitwind:test("EnumName returns nil for unmapped numeric value", function()
        local name = enumname.dialogueType(999)
        unitwind:expect(name).toBe(nil)
    end)

    unitwind:test("BitFlagNames returns empty array for invalid value type", function()
        local names = enumname.actionFlag("bad") ---@diagnostic disable-line: param-type-mismatch
        unitwind:expect(names).toBe(nil)
    end)

    unitwind:test("BitFlagNames returns nil for nil value", function()
        local names = enumname.actionFlag(nil) ---@diagnostic disable-line: param-type-mismatch
        unitwind:expect(names).toBe(nil)
    end)

    unitwind:test("BitFlagNames returns empty array when non-zero value matches no flags", function()
        local names = enumname.actionFlag(0x4)
        unitwind:expect(table.size(names)).toBe(0)
    end)

    unitwind:test("BitFlagNames returns empty array for unnamed zero-value state", function()
        local names = enumname.actionFlag(0)
        unitwind:expect(table.size(names)).toBe(0)
    end)

    unitwind:test("BitFlagNames returns matched names when some bits remain unmatched", function()
        local names = enumname.actionFlag(tes3.actionFlag.doorClosing + 0x4)
        unitwind:expect(table.concat(names, "|")).toBe("doorClosing")
    end)

    -- skill uses tes3.skillName (pre-built number->string) and returns display names.
    unitwind:test("skill returns display name from tes3.skillName", function()
        unitwind:expect(enumname.skill(tes3.skill.block)).toBe("Block")
        unitwind:expect(enumname.skill(tes3.skill.mediumArmor)).toBe("Medium Armor")
    end)

    unitwind:test("skillName is an alias for skill", function()
        unitwind:expect(enumname.skillName(tes3.skill.block)).toBe(enumname.skill(tes3.skill.block))
    end)

    -- attribute uses tes3.attributeName (pre-built number->string).
    unitwind:test("attribute returns name from tes3.attributeName", function()
        unitwind:expect(enumname.attribute(tes3.attribute.strength)).toBe("strength")
        unitwind:expect(enumname.attribute(tes3.attribute.luck)).toBe("luck")
    end)

    unitwind:test("attributeName is an alias for attribute", function()
        unitwind:expect(enumname.attributeName(tes3.attribute.strength)).toBe(enumname.attribute(tes3.attribute.strength))
    end)

    -- specialization uses tes3.specializationName (pre-built number->string).
    unitwind:test("specialization returns name from tes3.specializationName", function()
        unitwind:expect(enumname.specialization(tes3.specialization.combat)).toBe("combat")
        unitwind:expect(enumname.specialization(tes3.specialization.stealth)).toBe("stealth")
    end)

    unitwind:test("specializationName is an alias for specialization", function()
        unitwind:expect(enumname.specializationName(tes3.specialization.combat)).toBe(enumname.specialization(tes3
        .specialization.combat))
    end)

    unitwind:finish()

    return { testsPassed = unitwind.testsPassed, testsFailed = unitwind.testsFailed }
end

return this
