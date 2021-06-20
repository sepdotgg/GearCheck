-- BEGIN_WEAKAURA_CODE

-- CONSTANTS
local REQUEST_MSG_PREFIX = "GCWA_REQ"
local RESPOND_MSG_PREFIX = "GCWA_RES"
local CHAT_LINK_TYPE = "garrmission"
local CHAT_LINK_ADDON_NAME = "gearcheckwa"
local CHAT_LINK_PATTERN = "%[GearCheck: ([^%s]+)%]"
local CHAT_LINK_TEMPLATE = "|H%s:%s|h|cFF00BFFF[GearCheck: %s]|h|r"
local EXTRACT_CHAR_NAME_PATTERN = "%[GearCheck: ([^%s]+)%]"
local EQUIPPED_ITEMS_ACTION = "EQUIPPED_ITEMS"
local EQUIPPED_ITEMS_ACTION_PATTERN = "EQUIPPED_ITEMS:([^%s]+)"
local SAVED_VARIABLES_KEY = "GCWA_POINT"
local GLOBAL_GEARCHECK_ADDON_KEY = "GearCheckWA_Addon"
local GLOBAL_GEARCHECK_FRAMES_KEY = "GearCheckWA_Frames"
local GLOBAL_GEARCHECK_WA_KEY = "GearCheckWA_Aura"
local RAND_STR_CHARSET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
local REQUEST_THROTTLE_SEC = 5

_G[GLOBAL_GEARCHECK_WA_KEY] = {}
local GearCheckAura = _G[GLOBAL_GEARCHECK_WA_KEY]

GearCheckAura.env = aura_env

-- Scoped variables

--- Valid Max Levels based on the expansion ID from GetExpansionLevel()
GearCheckAura.MAX_LEVEL = {
    [0] = 60,
    [1] = 70,
    [2] = 80,
    [3] = 85,
    [4] = 90,
    [5] = 100,
    [6] = 110,
    [7] = 120,
    [8] = 60
}

--- Valid Slot IDs for each Item Equipment Type
GearCheckAura.ITEM_EQUIP_LOCS = {
    ["INVTYPE_AMMO"] = {0},
    ["INVTYPE_HEAD"] = {1},
    ["INVTYPE_NECK"] = {2},
    ["INVTYPE_SHOULDER"] = {3},
    ["INVTYPE_BODY"] = {4},
    ["INVTYPE_CHEST"] = {5},
    ["INVTYPE_ROBE"] = {5},
    ["INVTYPE_WAIST"] = {6},
    ["INVTYPE_LEGS"] = {7},
    ["INVTYPE_FEET"] = {8},
    ["INVTYPE_WRIST"] = {9},
    ["INVTYPE_HAND"] = {10},
    ["INVTYPE_FINGER"] = {11, 12},
    ["INVTYPE_TRINKET"] = {13, 14},
    ["INVTYPE_CLOAK"] = {15},
    ["INVTYPE_WEAPON"] = {16, 17},
    ["INVTYPE_SHIELD"] = {17},
    ["INVTYPE_2HWEAPON"] = {16},
    ["INVTYPE_WEAPONMAINHAND"] = {16},
    ["INVTYPE_WEAPONOFFHAND"] = {17},
    ["INVTYPE_HOLDABLE"] = {17},
    ["INVTYPE_RANGED"] = {18},
    ["INVTYPE_THROWN"] = {18},
    ["INVTYPE_RANGEDRIGHT"] = {18},
    ["INVTYPE_RELIC"] = {18},
    ["INVTYPE_TABARD"] = {19},
}

GearCheckAura.env.lastIncomingRequest = { }
GearCheckAura.env.lastOutgoingRequest = { }
GearCheckAura.env.pendingTokens = { }
GearCheckAura.FRAME = _G[GLOBAL_GEARCHECK_FRAMES_KEY]

--- Log messages to DebugLog if it is installed
--- @param data string String to log to DebugLog if it is installed
function GearCheckAura.env:log(data)
    if DLAPI then DLAPI.DebugLog(GLOBAL_GEARCHECK_WA_KEY, data) end
end

--- Utility Functions

--- Gets the global GearCheck WeakAura context
--- This is the only method that should be used to reference the "GearCheckAura" local since its
--- reference is locked at the time of a function's declaration
--- 
--- This method ensures we always get the most up to date reference.
local function GetGCWA()
    return _G[GLOBAL_GEARCHECK_WA_KEY]
end

--- Title cases a string
--- @param str string The string to title case
--- @return string The string in title case
function GearCheckAura:titleCase(str)
    str = string.lower(str)
    return str:gsub("(%l)(%w*)", function(a,b) return string.upper(a)..b end)
end


--- Generates a random string of lenth "len"
--- @param len number The length of the random string to generate
function GearCheckAura:randomString(len)
    local str = ""
    for i = 0, len, 1 do
        local r = math.random(1, string.len(RAND_STR_CHARSET))
        local char = string.sub(RAND_STR_CHARSET, r, r)
        str = str .. char
    end
    return str
end

--- Wraps text in red for error/warning messages.
--- @param text string The text to wrap in red color
function GearCheckAura:errorText(text)
    return WrapTextInColorCode(text, "FFFF0000")
end

--- Wraps text in GearCheck blue color
--- @param text string The text to wrap in GearCheck blue color
function GearCheckAura:gearCheckColor(text)
    return WrapTextInColorCode(text, "FF00BFFF")
end

--- Checks if an item received from someone's gear check matches the slot that item is supposed to go in
--- Helps mitigate bad actors modifying their end of the code to send invalid item data for slots
--- @param itemEquipLoc string The item's equip location, as determined from GetItemInfo
--- @param slotId The slot ID the item is "supposed" to go in
function GearCheckAura:isItemValid(itemEquipLoc, slotId)
    local validLevels = self.ITEM_EQUIP_LOCS[itemEquipLoc]
    if (validLevels == nil) then
        return false
    end
    for i, validSlot in ipairs(validLevels) do
        if (validSlot == slotId) then
            return true
        end
    end
    return false
end

--- Simple check to see if the player's level data received is within the range of valid levels and is an integer
--- @param playerLevel number The player's level received from the gear check response
function GearCheckAura:isPlayerLevelValid(playerLevel)
    local currentExpansion = GetExpansionLevel()
    local maxLevel = self.MAX_LEVEL[currentExpansion]
    return (playerLevel <= maxLevel and playerLevel >= 1 and math.floor(playerLevel) == playerLevel)
end

--- Generates a new request token for the target character name
--- The handler that displays the gear should only execute if the token in the response matches this request token
-- @param targetCharName string The target that is receiving the gear check request.
function GearCheckAura:addPendingToken(targetCharName)
    local token = self:randomString(8)
    self.env.pendingTokens[targetCharName] = token
    return token
end

--- Resets/Unsets any pending token for a target character
--- @param targetCharName string The target that is receiving the gear check request.
function GearCheckAura:resetToken(targetCharName)
    self.env:log("Resetting token for: " .. targetCharName)
    self.env.pendingTokens[targetCharName] = nil 
end

--- Checks if the token is pending for the target character
--- @param targetCharName string The target that is receiving the gear check request.
--- @param token string The token received in the response message.
function GearCheckAura:isPendingRequest(targetCharName, token)
    self.env:log("Checking token: [" .. targetCharName .. "] [" .. token .. "]")
    local pendingToken = self.env.pendingTokens[targetCharName]
    if (pendingToken == nil) then
        return false
    end
    return pendingToken == token
end

--- Updates the last incoming request from a character
--- @param charFullName string The full name/realm of the character requesting data.
function GearCheckAura:updateLastIncomingRequest(charFullName)
    local now = time()
    self.env.lastIncomingRequest[charFullName] = now
end

--- Updates the last out request to a character
--- @param charFullName string The full name/realm of the target character.
function GearCheckAura:updateLastOutgoingRequest(targetCharName)
    local now = time()
    self.env.lastOutgoingRequest[targetCharName] = now
end

--- Checks if an incoming requester is outside of the throttling limit
--- @param requesterFullName string The full name/realm of the character requesting data.
--- @return boolean True/false if the requester is allowed to request data.
function GearCheckAura:requesterCanRequest(requesterFullName)
    local now = time()
    local lastRequested = self.env.lastIncomingRequest[requesterFullName]
    if (lastRequested == nil) then
        return true
    end
    return (now - lastRequested) > REQUEST_THROTTLE_SEC
end

--- Checks if an outgoing request is within the throttling limit to the target character
--- @param requesterFullName string The full name/realm of the  target character.
--- @return boolean True/false if the outgoing request should proceed.
function GearCheckAura:canRequestFromTarget(targetCharName)
    local now = time()
    local lastRequested = self.env.lastOutgoingRequest[targetCharName]
    if (lastRequested == nil) then
        return true
    end
    return (now - lastRequested) > REQUEST_THROTTLE_SEC
end

--- Saves the GearCheck frame's current position to SavedVariables
--- @param frame table The main WeakAura Region frame
function GearCheckAura:savePoint(frame)
    local pos = {}
    local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint()
    pos.point = point
    pos.relativeTo = relativeTo
    pos.relativePoint = relativePoint
    pos.xOfs = xOfs
    pos.yOfs = yOfs
    
    WeakAurasSaved[SAVED_VARIABLES_KEY] = pos
end

--- Loads the main frame's saved position from Saved Variables and applies that position to the provied frame
--- @param frame table The frame to have its position set
function GearCheckAura:loadSavedPoint(frame)
    local savedPoint = WeakAurasSaved[SAVED_VARIABLES_KEY]
    if (savedPoint ~= nil) then
        frame:SetPoint(savedPoint.point, UIParent, savedPoint.relativePoint, savedPoint.xOfs, savedPoint.yOfs)
    end
end

--- Makes a Frame able to be moved and dragged
--- Saves the frame's position to WeakAuras saved variables
--- @param frame table The frame to make movable and have its position stored
function GearCheckAura:makeFrameMovable(frame)
    local GCWA = self; -- self is re-assigned in the anonymous functions below
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" and not self.isMoving then
                self:StartMoving();
                self.isMoving = true;
            end
    end)
    frame:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" and self.isMoving then
                self:StopMovingOrSizing();
                self.isMoving = false;
                GCWA:savePoint(self)
            end
    end)
    frame:SetScript("OnHide", function(self)
            if ( self.isMoving ) then
                self:StopMovingOrSizing();
                self.isMoving = false;
                GCWA:savePoint(self)
            end
    end)
end

--- Extracts a Character name and Realm from a Chat Link string.
--- @param str string The chat link string
--- @return table The character name/realm in the format of "Name-Realm"
function GearCheckAura:extractCharacterFromChatLink(str)
    local _, _, characterName = str:find(EXTRACT_CHAR_NAME_PATTERN)
    return characterName
end

--- Builds a table of equipped items for the current player.
---
--- @return table Table of slot IDs to an indexed table of {itemLink, itemTextureId}
function GearCheckAura:getEquippedItems(token)
    local equipped = {}
    equipped["token"] = token
    equipped["items"] = {}
    equipped["level"] = UnitLevel("player")

    equipped["talents"] = {
        [1] = select(3, GetTalentTabInfo(1)),
        [2] = select(3, GetTalentTabInfo(2)),
        [3] = select(3, GetTalentTabInfo(3)),
    }
    
    local _, playerClass, _ = UnitClass("player")
    
    equipped["class"] = self:titleCase(playerClass)
    
    local numItems = 0
    local ilvlSum = 0
    for i = 1, 19 do
        local itemLink = GetInventoryItemLink("player", i)
        if itemLink ~= nil then
            local _, _, _, itemLevel, _, _, _, _, itemEquipLoc, itemTexture, _ = GetItemInfo(itemLink)
            if (i == 4 or i == 19) then
                -- shirts and tabards should not be included in the calculation
            elseif (itemEquipLoc == "INVTYPE_2HWEAPON") then
                -- 2 handed weapons count for both slots
                ilvlSum = ilvlSum + (itemLevel * 2)
            else
                ilvlSum = ilvlSum + itemLevel
            end
            
            equipped["items"][i] = {
                [0] = itemLink,
                [1] = itemTexture
            }
        end
    end
    
    -- there's 17 slots included in the ilvl calculation
    -- two handers count twice because one slot will always be empty
    equipped["ilvl"] = math.floor((ilvlSum / 17) * 100)/100
    
    return equipped
end

--- Sends an addon channel comm message to request a player's equipped items to the specified player.
--- @param characterName string Name/Realm of the character who should receive the request on the addon channel.
function GearCheckAura:requestPlayerEquippedItems(characterName, token)
    self.env:log("Requesting info from " .. characterName .. " [" .. token .. "]")
    -- check if we can request from this character
    self.env.GEAR_CHECK:SendCommMessage(REQUEST_MSG_PREFIX, EQUIPPED_ITEMS_ACTION .. ":" .. token, "WHISPER", characterName)
end

--- Handles the "EQUIPPED_ITEMS" Action
--- @param requestingCharacter string Name/Realm of the user who should receive the equipped items response.
function GearCheckAura:equippedItemsAction(requestingCharacter, token)
    local equipped = self:getEquippedItems(token)
    -- respond to the requester
    local serialized = self.env.GEAR_CHECK:Serialize(equipped)
    self.env.GEAR_CHECK:SendCommMessage(RESPOND_MSG_PREFIX, serialized, "WHISPER", requestingCharacter)
end

-- Addon Message Event Handlers

--- Simple wrapper for the chat link click method that will always use the most up to date GearCheck WA
--- WARNING: If this method changes, users will need to /reload to get the changes.
GearCheckAura.chatLinkClickEntry = function(...)
    GetGCWA():handleChatLinkClick(...)
end

--- Handles clicking on Gear Check links
--- See SetItemRef: https://wowpedia.fandom.com/wiki/API_SetItemRef
--- @param link string The link type and addon discriminator that the link used
--- @param text string The raw text of the link that was clicked
function GearCheckAura:handleChatLinkClick(link, text)
    local linkType, addon = strsplit(":", link)
    if linkType == CHAT_LINK_TYPE and addon == CHAT_LINK_ADDON_NAME then
        
        local characterName = self:extractCharacterFromChatLink(text)
        if (characterName == nil) then
            return
        end
        -- Are we clicking the same link too quickly?
        local shouldRequest = self:canRequestFromTarget(characterName)
        if (shouldRequest) then
            self:updateLastOutgoingRequest(characterName)
            
            -- generate a new request token
            local token = self:addPendingToken(characterName)
            -- Request equipment info
            self:requestPlayerEquippedItems(characterName, token)
            self.FRAME.frames:ResetAll()
            self.FRAME.parent:Show()
        else
            self.env:log("Outgoing requests throttled to target: " .. characterName)
        end
    end
end

--- Handles addon channel requests for the player's equipped items
--- @param event string The raw event type which triggered the request.
--- @param action string The message body, in our case this is the Action that should be performed.
--- @param channelType string The channel which originated the message. Eg, "PARTY", "WHISPER"
--- @param sender string The character that initiated the request for a player's equipped items by clicking a link.
function GearCheckAura:handleEquippedItemsRequest(event, action, channelType, sender)
    if (channelType ~= "WHISPER") then -- only respond to requests on the whisper channel
        return
    end
    
    self.env:log("Received request from: " .. sender)
    
    -- check if this user is being throttled
    local canRequest = self:requesterCanRequest(sender)
    if (self:requesterCanRequest(sender)) then
        local _, _, token = action:find(EQUIPPED_ITEMS_ACTION_PATTERN)
        if (token == nil) then
            self.env:log("No token was included in the request from: " .. sender)
            return
        else
            self:updateLastIncomingRequest(sender)
            self:equippedItemsAction(sender, token)
        end
    else
        self.env:log("Requester is being throttled: " .. sender)
    end
end

--- Calculates a GearScore from a player's class and equipped items, if GearScore is installed
--- Otherwise returns nil
--- @param equippedItemsTable table Equipped items table. Key is slot ID with value being {itemLink, itemTextureId}
--- @param The class of the player
function GearCheckAura:calculateGearScore(equippedItemsTable, playerClass)
    if (GearScore_GetItemScore == nil) then
        return nil
    end

    local gearScore = 0
    local tempScore = 0

    for i, v in pairs(equippedItemsTable) do
        if (v[0] ~= nil) then
            local gsItemLink = select(2, GetItemInfo(v[0])) -- GS doesn't like the object unless we re-get it?
            local tempScore, _ = GearScore_GetItemScore(gsItemLink)
            if ( i == 16 or i == 17 ) and ( playerClass:upper() == "HUNTER" ) then tempScore = tempScore * 0.3164 end
            if ( i == 18 ) and ( playerClass:upper() == "HUNTER" ) then tempScore = tempScore * 5.3224 end
            gearScore = gearScore + tempScore
        end
    end
    return gearScore
end

--- Displays the equipped items which came in in a response
--- @param characterName string The name/realm of the character.
--- @param equippedItemsTable table Equipped items table. Key is slot ID with value being {itemLink, itemTextureId}
function GearCheckAura:displayEquippedItems(characterInfo, equippedItemsTable)
    local name = characterInfo["name"]
    local class = characterInfo["class"]
    local level = characterInfo["level"]
    local ilvl = characterInfo["ilvl"]
    local talents = characterInfo["talents"]

    if (not self:isPlayerLevelValid(level)) then
        self.env:log("Invalid level received from: " .. name .. ", level: " .. (level or "nil"))
        print(self:gearCheckColor("GearCheck: ") .. self:errorText("WARNING") .. ": The response received from \"" .. name .. "\" contains invalid or tampered data and and could not be confirmed.")
        PlaySound(5274)
    end
    
    local topText = name
    if class and level then
        local r, g, b = GetClassColor(class:upper())
        local classColor = CreateColor(r, g, b)
        name = classColor:WrapTextInColorCode(name)
        topText = ("%s\n%d %s"):format(
            name,
            level,
            class
        )
    end
    
    local bottomText = ""
    if (ilvl ~= nil) then
        bottomText = ("ilvl %.2f"):format(ilvl)
    end

    local talentText = ""
    if (talents ~= nil) then
        talentText = ("%d / %d / %d"):format(talents[1], talents[2], talents[3])
    end

    local gearScoreText = ""
    if (class ~= nil) then
        local gearScore = self:calculateGearScore(equippedItemsTable, class)
        
        if (gearScore ~= nil and GearScore_GetQuality ~= nil) then
            local gsTxt = ("%d"):format(gearScore)
            local r, b, g = GearScore_GetQuality(gearScore)
            local gsColor = CreateColor(r, g, b)
            gearScoreText = "GearScore: " .. gsColor:WrapTextInColorCode(gsTxt)
        end
    end
    
    local haveShownEquipWarning = false

    for i, v in pairs(equippedItemsTable) do
        local itemEquipLoc = select(9, GetItemInfo(v[0]))
        if (itemEquipLoc ~= nil and not self:isItemValid(itemEquipLoc, i) and not haveShownEquipWarning) then
            self.env:log("Invalid level received from: " .. name .. ", itemEquipLoc: " .. itemEquipLoc .. " for slot ID " .. i)
            print(self:gearCheckColor("GearCheck: ") .. self:errorText("WARNING") .. ": The response received from \"" .. name .. "\" contains invalid or tampered data and and could not be confirmed.")
            haveShownEquipWarning = true
            PlaySound(5274)
        end

        self.FRAME.frames:SetSlot(i, v[0], v[1])
    end
    self.FRAME.frames:SetText(topText, bottomText, talentText, gearScoreText)
    self:makeFrameMovable(self.FRAME.parent)
end

--- Handles the Equipped Items response from a player
--- @param event string The raw event type which triggered the response
--- @param equipped string Ace3 serialized string which contains the equipped items table
--- @param channelType string The channel which originated the message. Eg, "PARTY", "WHISPER"
--- @param sender string The character which responded to the equipped items request.
function GearCheckAura:handleEquippedItemsResponse(event, equipped, channelType, sender)
    self.env:log("Received Response from " .. sender)
    if (channelType ~= "WHISPER") then
        return -- only respond to whispers to reduce chatter
    end
    
    local success, deserialized = self.env.GEAR_CHECK:Deserialize(equipped)
    
    if (not success) then
        error(("Failed to deserialize Equipped Items"):format(tostring(equipped)), 2)
        return -- there was some error deserializing, do nothing
    end
    
    -- check the token
    local token = deserialized["token"]
    if (token == nil) then
        self.env:log("Empty token in the response from sender: " .. sender)
        return
    end
    
    if (self:isPendingRequest(sender, token)) then
        self:resetToken(sender)
        
        local characterInfo = {
            ["name"] = sender,
            ["class"] = deserialized["class"] or nil,
            ["level"] = deserialized["level"] or nil,
            ["ilvl"] = deserialized["ilvl"] or nil,
            ["talents"] = deserialized["talents"] or nil,
        }
        
        -- Display the items
        self:displayEquippedItems(characterInfo, deserialized["items"])
    else
        self.env:log("Received token is not valid. [" .. sender .. "] [" .. token .. "]")
    end
    
end

--- Simple wrapper for the REQUEST comm method that will always use the most up to date GearCheck WA
--- WARNING: If this method changes, users will need to /reload to get the changes.
GearCheckAura.requestCommEntry = function(...)
    GetGCWA():handleEquippedItemsRequest(...)
end

--- Hook function which filters Gear Check strings in chat and turns them into clickable links
local function chatLinkFilter(_, event, msg, player, l, cs, t, flag, channelId, ...)
    if flag == "GM" or flag == "DEV" or (event == "CHAT_MSG_CHANNEL" and type(channelId) == "number" and channelId > 0) then
        return
    end
    
    local newMsg = ""
    local remaining = msg
    local done
    
    repeat
        local start, finish, characterName = remaining:find(CHAT_LINK_PATTERN)
        if(characterName) then
            characterName = characterName:gsub("|c[Ff][Ff]......", ""):gsub("|r", "")
            newMsg = newMsg..remaining:sub(1, start-1)
            local trimmedPlayer = Ambiguate(characterName, "none")
            local chatLink = string.format(CHAT_LINK_TEMPLATE, CHAT_LINK_TYPE, CHAT_LINK_ADDON_NAME, trimmedPlayer)
            newMsg = newMsg..chatLink
            remaining = remaining:sub(finish + 1)
        else
            done = true
        end
    until(done)
    if newMsg ~= "" then
        return false, newMsg, player, l, cs, t, flag, channelId, ...
    end
end

--- Simple wrapper for the RESPONSE comm method that will always use the most up to date GearCheck WA
--- WARNING: If this method changes, users will need to /reload to get the changes.
GearCheckAura.responseCommEntry = function(...)
    GetGCWA():handleEquippedItemsResponse(...)
end

--- Initialize the main Item Frames region and slots
--- @param parentRegion table The parent region which will anchor the frames. Normally this is aura_env.region.
--- @returns table An array/table of frames for each slot.
function GearCheckAura:initItemFrames(parentRegion)
    local frames = {}
    local SIZE = 32
    local defaultSlotTextures = {[1] = 136516, [2] = 136519, [3] = 136526, [4] = 136525, [5] = 136512, [6] = 136529, [7] = 136517, [8] = 136513, [9] = 136530, [10] = 136515, [11] = 136514, [12] = 136514, [13] = 136528, [14] = 136528, [15] = 136512, [16] = 136518, [17] = 136524, [18] = 136520, [19] = 136527}
    
    self:makeFrameMovable(parentRegion)
    self:loadSavedPoint(parentRegion)
    
    local function makeFrame(slotId)
        local f = CreateFrame("Button", nil, parentRegion)
        f:SetSize(SIZE, SIZE)
        
        -- texture stuff
        f.tex = f:CreateTexture()
        f.tex:SetAllPoints(f)
        f.defaultTexture = defaultSlotTextures[slotId]
        f.itemTexture = nil
        function f:SetItemTexture(texture)
            f.itemTexture = texture
            local itemTexture = f.itemTexture or f.defaultTexture
            f.tex:SetTexture(itemTexture)
        end
        
        -- tooltip stuff
        f:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if self.itemLink then
                    GameTooltip:SetHyperlink(self.itemLink)
                    GameTooltip:Show()
                end
        end)
        f:SetScript("OnLeave", function(self) GameTooltip:Hide() end)
        function f:SetItemLink(link)
            f.itemLink = link
        end
        
        -- re-linking
        f:RegisterForClicks("LeftButtonDown")
        f:SetScript("OnClick", function(self)
                if IsShiftKeyDown() and self.itemLink then
                    local editbox = GetCurrentKeyBoardFocus()
                    if editbox then
                        editbox:Insert(self.itemLink) 
                    end
                elseif IsControlKeyDown() and self.itemLink then
                    DressUpItemLink(self.itemLink)
                end
        end)
        
        f:Show()
        return f
    end
    
    for i=1,#defaultSlotTextures do
        frames[i] = makeFrame(i)
        frames[i]:SetItemLink(nil)
        frames[i]:SetItemTexture(nil)
    end
    
    -- align left col
    local anchor = parentRegion
    frames[1]:SetPoint("TOPLEFT", anchor, "TOPLEFT", SIZE/2, SIZE*-1.5)
    anchor = frames[1]
    for _,i in ipairs({2, 3, 15, 5, 4, 19, 9, 16}) do
        frames[i]:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT")
        anchor = frames[i]
    end
    -- align bottom row
    for _,i in ipairs({17, 18}) do
        frames[i]:SetPoint("TOPLEFT", anchor, "TOPRIGHT")
        anchor = frames[i]
    end
    -- align right col
    for _,i in ipairs({14, 13, 12, 11, 8, 7, 6, 10}) do
        frames[i]:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT")
        anchor = frames[i]
    end
    
    -- close button
    local closeButton = CreateFrame("Button", nil, parentRegion, "UIPanelCloseButton")
    closeButton:SetSize(SIZE, SIZE)
    closeButton:SetPoint("TOPRIGHT")
    closeButton:Show()
    
    -- text
    frames.defaultTopText = "Loading..."
    frames.topText = parentRegion:CreateFontString(nil, "ARTWORK", "GameTooltipText")
    frames.topText:SetPoint("TOPLEFT", SIZE/4, -1*SIZE/4)
    frames.topText:SetText(frames.defaultTopText)
    
    frames.defaultIlvlText = ""

    frames.ilvlBtnFrame = CreateFrame("Button", nil, parentRegion)
    frames.ilvlBtnFrame:SetSize(SIZE*2, SIZE)
    frames.ilvlBtnFrame:SetPoint("BOTTOM", 0, SIZE/4)
    frames.ilvlText = frames.ilvlBtnFrame:CreateFontString(nil, "ARTWORK", "GameTooltipText")
    frames.ilvlText:SetPoint("CENTER")
    frames.ilvlText:SetText(frames.defaultIlvlText)

    frames.defaultTalentText = ""
    frames.talentText = parentRegion:CreateFontString(nil, "ARTWORK", "GameTooltipText")
    frames.talentText:SetPoint("BOTTOM", 0, SIZE)
    frames.talentText:SetText(frames.defaultTalentText)

    frames.defaultGearScoreText = ""
    
    function frames:ResetAll()
        for i=1,#frames do
            frames[i]:SetItemLink(nil)
            frames[i]:SetItemTexture(nil)
        end
        frames:SetText(frames.defaultTopText, frames.defaultIlvlText, frames.defaultTalentText, frames.defaultGearScoreText)
    end
    
    function frames:SetSlot(slotId, itemLink, itemTexture)
        frames[slotId]:SetItemLink(itemLink)
        frames[slotId]:SetItemTexture(itemTexture)
    end
    
    function frames:SetText(topText, ilvlText, talentText, gearScoreText)
        frames.topText:SetText(topText)
        frames.ilvlText:SetText(ilvlText)
        frames.talentText:SetText(talentText)
        frames.gearScoreText = gearScoreText

        frames.ilvlBtnFrame:SetScript("OnEnter", function()
            if (frames.gearScoreText ~= "") then
                GameTooltip:SetOwner(frames.ilvlBtnFrame, "ANCHOR_RIGHT")
                GameTooltip:SetText(frames.gearScoreText)
                GameTooltip:Show()
            end
        end)

        frames.ilvlBtnFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    
    return frames
end

--- Clear/hide any frames that previously existed
--- @param frames table the "GearCheckAura.FRAME.frames" table which contains all of the UI frames.
function GearCheckAura:clearFrames(frames)
    for i, f in ipairs(frames) do
        f:Hide()
        f:SetScript("OnClick", nil)
        f:SetScript("OnEnter", nil)
        f:SetScript("OnLeave", nil)
    end
    
    if (frames.topText ~= nil) then
        frames.topText:Hide()
    end
    if (frames.bottomText ~= nil) then
        frames.bottomText:Hide()
    end
    if (frames.ilvlText ~= nil) then
        frames.ilvlText:Hide()
    end
    if (frames.talentText ~= nil) then
        frames.talentText:Hide()
    end
    if (frames.ilvlBtnFrame ~= nil) then
        frames.ilvlBtnFrame:Hide()
        frames.ilvlBtnFrame:SetScript("OnEnter", nil)
        frames.ilvlBtnFrame:SetScript("OnLeave", nil)
    end
end

--- Load up the item frames attached to the WA region, but only if they don't already exist
function GearCheckAura:loadFrames()
    -- check if there's any existing frames, clear them if so
    local existingFrames = _G[GLOBAL_GEARCHECK_FRAMES_KEY]
    if (existingFrames ~= nil) then
        self.env:log("Clearing previous GearCheckWA frames")
        self:clearFrames(existingFrames.frames)
    end

    -- reset the frame context and create new frames
    _G[GLOBAL_GEARCHECK_FRAMES_KEY] = { }
    self.FRAME = _G[GLOBAL_GEARCHECK_FRAMES_KEY]
    self.FRAME.parent = self.env.region
    self.FRAME.frames = self:initItemFrames(self.env.region)
end

-- Initialize the Addon
local function loadAddon()
    local AceComm = LibStub("AceComm-3.0")
    local AceEvent = LibStub("AceEvent-3.0")
    local AceSerializer = LibStub("AceSerializer-3.0")

    local GCWA = GetGCWA()
    
    GCWA.env.GEAR_CHECK = {}
    _G[GLOBAL_GEARCHECK_ADDON_KEY] = GCWA.env.GEAR_CHECK
    
    AceComm:Embed(GCWA.env.GEAR_CHECK)
    AceEvent:Embed(GCWA.env.GEAR_CHECK)
    AceSerializer:Embed(GCWA.env.GEAR_CHECK)
    
    -- register event channels
    GCWA.env.GEAR_CHECK:RegisterComm(REQUEST_MSG_PREFIX, GCWA.requestCommEntry)
    GCWA.env.GEAR_CHECK:RegisterComm(RESPOND_MSG_PREFIX, GCWA.responseCommEntry)
    
    -- set up the handler for clicking the chat links
    hooksecurefunc("SetItemRef", GCWA.chatLinkClickEntry)
    
    -- filter chat links into our clickable format
    ChatFrame_AddMessageEventFilter("CHAT_MSG_GUILD", chatLinkFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_OFFICER", chatLinkFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_PARTY", chatLinkFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_PARTY_LEADER", chatLinkFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_RAID", chatLinkFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_RAID_LEADER", chatLinkFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", chatLinkFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", chatLinkFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_BN_WHISPER", chatLinkFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_BN_WHISPER_INFORM", chatLinkFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_INSTANCE_CHAT", chatLinkFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_INSTANCE_CHAT_LEADER", chatLinkFilter)
    
    GCWA:loadFrames()
end

local loadedAddon = _G[GLOBAL_GEARCHECK_ADDON_KEY]

if (loadedAddon ~= nil) then
    GearCheckAura.env.GEAR_CHECK = loadedAddon
    GearCheckAura:makeFrameMovable(GearCheckAura.env.region)
    GearCheckAura:loadSavedPoint(GearCheckAura.env.region)
    GearCheckAura:loadFrames()
else
    loadAddon()
end