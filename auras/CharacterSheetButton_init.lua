if not aura_env.clickableFrame then
    local f = CreateFrame("Button", nil, aura_env.region, "GameMenuButtonTemplate")

    f:SetAllPoints()
    f:SetText("Link")

    local name, realm = UnitFullName("player")
    local charFullName = name
    if realm then
        charFullName = name.."-"..realm
    f.GearCheckLink = "[GearCheck: "..charFullName.."]"

    f:SetScript("OnClick", function(self)
            if (IsShiftKeyDown()) then
                local editbox = GetCurrentKeyBoardFocus()
                if (editbox) then
                    editbox:Insert(self.GearCheckLink);
                end
            end
    end)

    f:SetScript("OnEnter", function(self) 
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText( "|cFF00BFFFGearCheck|r\nShift+Click to create a link in chat\nThe recipient will need to have the GearCheck WeakAura installed." )
            GameTooltip:Show()
    end)

    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    aura_env.clickableFrame = f
end

aura_env.clickableFrame:Show()
