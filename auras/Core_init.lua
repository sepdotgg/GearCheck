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
local SAVED_VARIABLES_KEY = "GCWA_POINT"
local GLOBAL_GEARCHECK_KEY = "GEARCHECK_WA"

_G[GLOBAL_GEARCHECK_KEY] = {}
local aura_addon = _G[GLOBAL_GEARCHECK_KEY]

aura_addon.env = aura_env

--- Utility Functions

--- Log messages to DebugLog if it is installed
--- @param data string String to log to DebugLog if it is installed
function aura_addon.env:log(data)
    if DLAPI then DLAPI.DebugLog(GLOBAL_GEARCHECK_KEY, data) end
end

--- Saves the GearCheck frame's current position to SavedVariables
--- @param frame table The main WeakAura Region frame
local function savePoint(frame)
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
local function loadSavedPoint(frame)
    local savedPoint = WeakAurasSaved[SAVED_VARIABLES_KEY]
    if (savedPoint ~= nil) then
        frame:SetPoint(savedPoint.point, UIParent, savedPoint.relativePoint, savedPoint.xOfs, savedPoint.yOfs)
    end
end

--- Makes a Frame able to be moved and dragged
--- Saves the frame's position to WeakAuras saved variables
--- @param frame table The frame to make movable and have its position stored
local function makeFrameMovable(frame)
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
                savePoint(self)
            end
    end)
    frame:SetScript("OnHide", function(self)
            if ( self.isMoving ) then
                self:StopMovingOrSizing();
                self.isMoving = false;
                savePoint(self)
            end
    end)
end

--- Extracts a Character name and Realm from a Chat Link string.
--- @param str string The chat link string
--- @return table The character name/realm in the format of "Name-Realm"
local function extractCharacterFromChatLink(str)
    local _, _, characterName = str:find(EXTRACT_CHAR_NAME_PATTERN)
    return characterName
end

--- Builds a table of equipped items for the current player.
---
--- @return table Table of slot IDs to an indexed table of {itemLink, itemTextureId}
local function getEquippedItems()
    local equipped = {}
    for i = 1, 19 do
        local itemLink = GetInventoryItemLink("player", i)
        if itemLink ~= nil then
            local _, _, _, _, _, _, _, _, _, itemTexture, _ = GetItemInfo(itemLink)
            equipped[i] = {
                [0] = itemLink,
                [1] = itemTexture
            }
        end
    end
    return equipped
end

--- Sends an addon channel comm message to request a player's equipped items to the specified player.
--- @param characterName string Name/Realm of the character who should receive the request on the addon channel.
local function requestPlayerEquippedItems(characterName)
    aura_addon.env:log("Requesting info from " .. characterName)
    aura_addon.env.GEAR_CHECK:SendCommMessage(REQUEST_MSG_PREFIX, EQUIPPED_ITEMS_ACTION, "WHISPER", characterName)
end

--- Handles the "EQUIPPED_ITEMS" Action
--- @param requestingCharacter string Name/Realm of the user who should receive the equipped items response.
local function equippedItemsAction(requestingCharacter)
    local equipped = getEquippedItems()
    -- respond to the requester
    local serialized = aura_addon.env.GEAR_CHECK:Serialize(equipped)
    aura_addon.env.GEAR_CHECK:SendCommMessage(RESPOND_MSG_PREFIX, serialized, "WHISPER", requestingCharacter)
end

-- Addon Message Event Handlers

--- Handles clicking on Gear Check links
--- See SetItemRef: https://wowpedia.fandom.com/wiki/API_SetItemRef
--- @param link string The link type and addon discriminator that the link used
--- @param text string The raw text of the link that was clicked
local function handleChatLinkClick(link, text)
    local linkType, addon = strsplit(":", link)
    if linkType == CHAT_LINK_TYPE and addon == CHAT_LINK_ADDON_NAME then
        
        local characterName = extractCharacterFromChatLink(text)
        if (characterName == nil) then
            return
        end
        -- Request equipment info
        requestPlayerEquippedItems(characterName)
    end
end

--- Handles addon channel requests for the player's equipped items
--- @param event string The raw event type which triggered the request.
--- @param action string The message body, in our case this is the Action that should be performed.
--- @param channelType string The channel which originated the message. Eg, "PARTY", "WHISPER"
--- @param sender string The character that initiated the request for a player's equipped items by clicking a link.
local function handleEquippedItemsRequest(event, action, channelType, sender)
    if (channelType ~= "WHISPER") then -- only respond to requests on the whisper channel
        return
    end
    
    aura_addon.env:log("Received request from: " .. sender)
    
    if (action == EQUIPPED_ITEMS_ACTION) then
        equippedItemsAction(sender)
    end
end

--- Displays the equipped items which came in in a response
--- @param characterName string The name/realm of the character.
--- @param equippedItemsTable table Equipped items table. Key is slot ID with value being {itemLink, itemTextureId}
function displayEquippedItems(characterName, equippedItemsTable)
    aura_addon.env.frames:ResetAll()
    for i, v in pairs(equippedItemsTable) do
        aura_addon.env.frames:SetSlot(i, v[0], v[1])
    end
    makeFrameMovable(aura_addon.env.region)
    aura_addon.env.region:Show()
end

--- Handles the Equipped Items response from a player
--- @param event string The raw event type which triggered the response
--- @param equipped string Ace3 serialized string which contains the equipped items table
--- @param channelType string The channel which originated the message. Eg, "PARTY", "WHISPER"
--- @param sender string The character which responded to the equipped items request.
local function handleEquippedItemsResponse(event, equipped, channelType, sender)
    aura_addon.env:log("Received Response from " .. sender)
    if (channelType ~= "WHISPER") then
        return -- only respond to whispers to reduce chatter
    end
    
    local success, deserialized = aura_addon.env.GEAR_CHECK:Deserialize(equipped)
    
    if (not success) then
        error(("Failed to deserialize Equipped Items"):format(tostring(equipped)), 2)
        return -- there was some error deserializing, do nothing
    end
    -- Display the items
    displayEquippedItems(sender, deserialized)
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
            
            local chatLink = string.format(CHAT_LINK_TEMPLATE, CHAT_LINK_TYPE, CHAT_LINK_ADDON_NAME, characterName)
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

--- Initialize the main Item Frames region and slots
--- @param parentRegion table The parent region which will anchor the frames. Normally this is aura_env.region.
--- @returns table An array/table of frames for each slot.
local function initItemFrames(parentRegion)
    local frames = {}
    local SIZE = 32
    local defaultSlotTextures = {[1] = 136516, [2] = 136519, [3] = 136526, [4] = 136525, [5] = 136512, [6] = 136529, [7] = 136517, [8] = 136513, [9] = 136530, [10] = 136515, [11] = 136514, [12] = 136514, [13] = 136528, [14] = 136528, [15] = 136512, [16] = 136518, [17] = 136524, [18] = 136520, [19] = 136527}
    
    makeFrameMovable(parentRegion)
    loadSavedPoint(parentRegion)
    
    local function makeFrame(slotId)
        local f = CreateFrame("Frame", nil, parentRegion)
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
    
    function frames:ResetAll()
        for i=1,#frames do
            frames[i]:SetItemLink(nil)
            frames[i]:SetItemTexture(nil)
        end
    end
    
    function frames:SetSlot(slotId, itemLink, itemTexture)
        frames[slotId]:SetItemLink(itemLink)
        frames[slotId]:SetItemTexture(itemTexture)
    end
    
    return frames
end

-- Initialize the Addon
local function loadAddon()
    aura_addon.env.GEAR_CHECK = LibStub("AceAddon-3.0"):NewAddon("GearCheckWA", "AceComm-3.0", "AceEvent-3.0", "AceSerializer-3.0")
    
    -- register event channels
    aura_addon.env.GEAR_CHECK:RegisterComm(REQUEST_MSG_PREFIX, handleEquippedItemsRequest)
    aura_addon.env.GEAR_CHECK:RegisterComm(RESPOND_MSG_PREFIX, handleEquippedItemsResponse)
    
    -- set up the handler for clicking the chat links
    hooksecurefunc("SetItemRef", handleChatLinkClick)
    
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
    
    aura_addon.env.frames = initItemFrames(aura_addon.env.region)
    aura_addon.env.region:Hide()
end

local loadedAddon = LibStub("AceAddon-3.0"):GetAddon("GearCheckWA", true)

if (loadedAddon ~= nil) then
    aura_addon.env.GEAR_CHECK = loadedAddon
    makeFrameMovable(aura_addon.env.region)
    loadSavedPoint(aura_addon.env.region)
    aura_addon.env.frames = initItemFrames(aura_addon.env.region)
else
    loadAddon()
end
