local this = {}
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local logger = require("morrowind-mcp.logger").Get({ moduleName = "dialogue" })

---@type MCP.DialogueDefineContext|nil
local cachedStaticDialogueDefineContext = nil

---@alias MCP.DialogueDefineSourcePlayer tes3reference|nil -- TODO mobile player?
---@alias MCP.DialogueDefineSourceActor tes3actor|tes3container|tes3containerInstance|tes3creature|tes3creatureInstance|tes3npc|tes3npcInstance|nil

---@class MCP.DialogueDefineSourceContext
---@field player MCP.DialogueDefineSourcePlayer
---@field actor MCP.DialogueDefineSourceActor
---@field dialogueInfo tes3dialogueInfo?
---@field cell tes3cell?
---@field npcFaction tes3faction?

---@class MCP.DialogueDefineContext
---@field pcname string?
---@field pcrace string?
---@field pcclass string?
---@field pccrimelevel string?
---@field name string?
---@field race string?
---@field class string?
---@field faction string?
---@field rank string?
---@field pcrank string?
---@field cell string?
---@field pcnextrank string? -- TODO reserved token context for %pcnextrank / %nextpcrank (not implemented)
---@field nextpcrank string? -- TODO reserved alias token for %nextpcrank (not implemented)
---@field actionactivate string?
---@field actionback string?
---@field actionforward string?
---@field actionjournal string?
---@field actionreadyitem string?
---@field actionreadymagic string?
---@field actionrestmenu string?
---@field actionslideleft string?
---@field actionslideright string?
---@field actionmenumode string?
---@field actionuse string?
---@field actioncrouch string?
---@field actionrun string?
---@field actiontogglerun string?
---@field actionjump string?
---@field actionnextweapon string?
---@field actionprevweapon string?
---@field actionnextspell string?
---@field actionprevspell string?
---@field crimegolddiscount string? -- TODO
---@field crimegoldturnin string? -- TODO

-- Normalize journal/topic text by keeping keyword markers, removing markup, and collapsing whitespace.
---@param value string?
---@return string
---@return table
function this.NormalizeDialogueText(value)
    if not value then
        return "", jsonrpc.array()
    end

    local topics = jsonrpc.array()
    local topicsSeen = {}
    local normalized = value
    -- Match topic markers like @Topic# and keep the inner topic text in the output.
    normalized = normalized:gsub("@([^#]+)#", function(keyword)
        local keywordKey = keyword ~= "" and keyword:lower() or ""
        -- Keep each topic only once, even if it appears multiple times or with different case.
        if keywordKey ~= "" and not topicsSeen[keywordKey] then
            topicsSeen[keywordKey] = true
            table.insert(topics, keyword)
        end
        return keyword
    end)
    -- Remove HTML-like tags while leaving the surrounding text in place.
    normalized = normalized:gsub("<[^>]+>", " ")
    -- Treat Windows line breaks as normal spaces so the text becomes a single paragraph.
    normalized = normalized:gsub("\r\n", " ")
    -- Treat Unix line breaks as normal spaces for the same reason.
    normalized = normalized:gsub("\n", " ")
    -- Treat stray carriage returns as spaces as well.
    normalized = normalized:gsub("\r", " ")
    -- Collapse repeated whitespace into one separator before trimming.
    normalized = normalized:gsub("%s+", " ")
    normalized = string.trim(normalized)

    return normalized, topics
end

-- Convert arbitrary values to text while preserving nil.
---@param value any
---@return string?
local function ToText(value)
    if value == nil then
        return nil
    end
    if type(value) == "string" then
        return value
    end
    return tostring(value)
end

-- Safely walk a nested field path without throwing when an intermediate value is missing.
---@param obj table
---@param keys string[]
---@return any
local function SafeGet(obj, keys)
    local current = obj
    for _, key in ipairs(keys) do
        if current == nil then
            return nil
        end
        local ok, nextValue = pcall(function()
            return current[key]
        end)
        if not ok then
            return nil
        end
        current = nextValue
    end
    return current
end

-- Player tokens prefer the live player reference, then its base object, then direct fields.
---@param player MCP.DialogueDefineSourcePlayer
---@return string?
local function ResolvePlayerName(player)
    return SafeGet(player, { "object", "name" })
        or SafeGet(player, { "baseObject", "name" })
        or SafeGet(player, { "name" })
end

---@param player MCP.DialogueDefineSourcePlayer
---@return string?
local function ResolvePlayerRace(player)
    return SafeGet(player, { "object", "race", "name" })
        or SafeGet(player, { "baseObject", "race", "name" })
        or SafeGet(player, { "race", "name" })
end

---@param player MCP.DialogueDefineSourcePlayer
---@return string?
local function ResolvePlayerClass(player)
    return SafeGet(player, { "object", "class", "name" })
        or SafeGet(player, { "baseObject", "class", "name" })
        or SafeGet(player, { "class", "name" })
end

---@param speaker MCP.DialogueDefineSourceActor
---@return string?
local function ResolveSpeakerName(speaker)
    return SafeGet(speaker, { "name" })
end

---@param speaker MCP.DialogueDefineSourceActor
---@return string?
local function ResolveSpeakerRace(speaker)
    return SafeGet(speaker, { "race", "name" })
end

---@param speaker MCP.DialogueDefineSourceActor
---@return string?
local function ResolveSpeakerClass(speaker)
    return SafeGet(speaker, { "class", "name" })
end

---@param speaker MCP.DialogueDefineSourceActor
---@return string?
local function ResolveSpeakerFaction(speaker)
    return SafeGet(speaker, { "faction", "name" })
end

---@param faction tes3faction|nil
---@param rankIndex number|nil
---@return string?
local function ResolveRankName(faction, rankIndex)
    local rankNumber = tonumber(rankIndex)
    if not rankNumber then
        return nil
    end

    -- Accept either 0-based or 1-based rank tables, depending on the source shape.
    local ranks = SafeGet(faction, { "ranks" })
    if type(ranks) == "table" then
        local rank = ranks[rankNumber + 1] or ranks[rankNumber]
        if rank then
            local rankName = ToText(SafeGet(rank, { "name" })) or ToText(rank)
            if rankName and rankName ~= "" then
                return rankName
            end
        end
    end

    return nil
end

-- Player crime level comes from the mobile bounty when available.
---@param player MCP.DialogueDefineSourcePlayer
---@return string?
local function ResolvePcCrimeLevel(player)
    return ToText(SafeGet(player, { "mobile", "bounty" }))
end

-- Resolve a token by lower-case lookup in the built context.
---@param tokenLower string
---@param context MCP.DialogueDefineContext?
---@return string?
local function ResolveDialogueDefineToken(tokenLower, context)
    if context == nil then
        return nil
    end

    return context[tokenLower]
end

-- Read a GMST text value once and return nil for missing or empty strings.
---@param gmstId tes3.gmst
---@return string?
local function ResolveGmstText(gmstId)
    local gameSetting = tes3.findGMST(gmstId)
    if not gameSetting then
        return nil
    end
    if gameSetting.value == "" then
        return nil
    end
    return gameSetting.value
end

-- Build and cache the static action token values that do not depend on dialogue source.
---@return MCP.DialogueDefineContext
local function BuildStaticDialogueDefineContext()
    if cachedStaticDialogueDefineContext then
        return cachedStaticDialogueDefineContext
    end

    -- Resolve static action tokens once and reuse them across all dialogue contexts.
    cachedStaticDialogueDefineContext = {
        actionactivate = ResolveGmstText(tes3.gmst.sActivate),
        actionback = ResolveGmstText(tes3.gmst.sBack),
        actionforward = ResolveGmstText(tes3.gmst.sForward),
        actionjournal = ResolveGmstText(tes3.gmst.sJournal),
        actionreadyitem = ResolveGmstText(tes3.gmst.sReady_Weapon),
        actionreadymagic = ResolveGmstText(tes3.gmst.sReady_Magic),
        actionrestmenu = ResolveGmstText(tes3.gmst.sRestKey),
        actionslideleft = ResolveGmstText(tes3.gmst.sLeft),
        actionslideright = ResolveGmstText(tes3.gmst.sRight),
        actionmenumode = ResolveGmstText(tes3.gmst.sMenu_Mode),
        actionuse = ResolveGmstText(tes3.gmst.sUse),
        actioncrouch = ResolveGmstText(tes3.gmst.sCrouch_Sneak),
        actionrun = ResolveGmstText(tes3.gmst.sRun),
        actiontogglerun = ResolveGmstText(tes3.gmst.sAlways_Run), -- or sToggleRunXbox?
        actionjump = ResolveGmstText(tes3.gmst.sJump),
        actionnextweapon = ResolveGmstText(tes3.gmst.sNextWeapon),
        actionprevweapon = ResolveGmstText(tes3.gmst.sPrevWeapon),
        actionnextspell = ResolveGmstText(tes3.gmst.sNextSpell),
        actionprevspell = ResolveGmstText(tes3.gmst.sPrevSpell),
    }

    return cachedStaticDialogueDefineContext
end

-- Build the per-source token context, then merge in the cached static action labels.
---@param source MCP.DialogueDefineSourceContext?
---@return MCP.DialogueDefineContext
function this.BuildDialogueDefineContext(source)
    source = source or {}
    local player = source.player
    local speaker = source.actor
    local dialogueInfo = source.dialogueInfo

    ---@type tes3faction|nil
    local speakerFaction = SafeGet(speaker, { "faction" })

    ---@type string?
    local resolvedCell = SafeGet(source, { "cell", "displayName" })

    local resolvedFaction = ResolveSpeakerFaction(speaker)

    -- Merge the cached static action tokens with the per-call dialogue values.
    local staticContext = BuildStaticDialogueDefineContext()

    return {
        -- Player-facing tokens.
        pcname = ResolvePlayerName(player),
        pcrace = ResolvePlayerRace(player),
        pcclass = ResolvePlayerClass(player),
        pccrimelevel = ResolvePcCrimeLevel(player),
        -- Speaker-facing tokens.
        name = ResolveSpeakerName(speaker),
        race = ResolveSpeakerRace(speaker),
        class = ResolveSpeakerClass(speaker),
        faction = resolvedFaction,
        rank = ResolveRankName(speakerFaction, SafeGet(dialogueInfo, { "npcRank" })),
        pcrank = ToText(SafeGet(dialogueInfo, { "pcRank" })),
        -- Cell context is read from the resolved source cell when available.
        cell = resolvedCell,
        -- Static action labels are cached because they only depend on GMST values.
        actionactivate = staticContext.actionactivate,
        actionback = staticContext.actionback,
        actionforward = staticContext.actionforward,
        actionjournal = staticContext.actionjournal,
        actionreadyitem = staticContext.actionreadyitem,
        actionreadymagic = staticContext.actionreadymagic,
        actionrestmenu = staticContext.actionrestmenu,
        actionslideleft = staticContext.actionslideleft,
        actionslideright = staticContext.actionslideright,
        actionmenumode = staticContext.actionmenumode,
        actionuse = staticContext.actionuse,
        actioncrouch = staticContext.actioncrouch,
        actionrun = staticContext.actionrun,
        actiontogglerun = staticContext.actiontogglerun,
        actionjump = staticContext.actionjump,
        actionnextweapon = staticContext.actionnextweapon,
        actionprevweapon = staticContext.actionprevweapon,
        actionnextspell = staticContext.actionnextspell,
        actionprevspell = staticContext.actionprevspell,
    }
end

-- Replace both percent and caret define tokens using the prepared context.
---@param text string?
---@param context MCP.DialogueDefineContext?
---@return string?
function this.ReplaceDialogueDefines(text, context)
    if text == nil then
        return nil
    end

    local unknown = {}
    -- Match either %Token or ^Token, then replace the token from the prepared context.
    local replaced = text:gsub("([%%%^])([%a_][%w_]*)", function(sigil, token)
        local tokenLower = token:lower()
        local replacement = ResolveDialogueDefineToken(tokenLower, context)
        if replacement ~= nil then
            return replacement
        end

        if not unknown[tokenLower] then
            unknown[tokenLower] = true
            logger:debug("Unresolved dialogue define token: %s", token)
        end
        return sigil .. token
    end)

    return replaced
end

return this
