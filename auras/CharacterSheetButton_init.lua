local aura_addon = {}

if not aura_env.clickableFrame then
    local r = aura_env.region
    aura_env.clickableFrame = CreateFrame("Button", "ConsumeButton", r, "SecureActionButtonTemplate")  
end

aura_env.clickableFrame:SetAllPoints()

aura_env.clickableFrame:SetScript("onClick", function()
        if (IsShiftKeyDown()) then
            
            local editbox = GetCurrentKeyBoardFocus()
            if(editbox) then
                if (aura_addon.charFullName == nil) then
                    local name, realm = UnitFullName("player")
                    if realm then
                        aura_addon.charFullName = name.."-".. realm
                    else
                        aura_addon.charFullName = name
                    end
                end
                editbox:Insert("[GearCheck: "..aura_addon.charFullName.."]");
            end
        end
end)

aura_env.clickableFrame:SetScript("onEnter", function() 
        GameTooltip_SetDefaultAnchor( GameTooltip, UIParent )
        GameTooltip:SetText( "GearCheck\nShift+Click to create a link in chat\nThe recipient will need to have the GearCheck WeakAura installed." )
        GameTooltip:Show()
end)

aura_env.clickableFrame:SetScript("onLeave", function() GameTooltip:Hide() end)

