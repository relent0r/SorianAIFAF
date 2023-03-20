local SUtils = import("/lua/ai/sorianutilities.lua")

---@param self Platoon
function AirUnitRefitSorian(self)
    for k, v in self:GetPlatoonUnits() do
        if not v.Dead and not v.RefitThread then
            v.RefitThread = v:ForkThread(AirUnitRefitThreadSorian, self:GetPlan(), self.PlatoonData)
        end
    end
end

---@param unit Unit
---@param plan any
---@param data any
function AirUnitRefitThreadSorian(unit, plan, data)
    unit.PlanName = plan
    if data then
        unit.PlatoonData = data
    end

    local aiBrain = unit:GetAIBrain()
    while not unit.Dead do
        local fuel = unit:GetFuelRatio()
        local health = unit:GetHealthPercent()
        if not unit.Loading and (fuel < 0.2 or health < 0.4) then

            -- Find air stage
            if aiBrain:GetCurrentUnits(categories.AIRSTAGINGPLATFORM - categories.CARRIER - categories.EXPERIMENTAL) > 0 then
                local unitPos = unit:GetPosition()
                local plats = AIUtils.GetOwnUnitsAroundPoint(aiBrain, categories.AIRSTAGINGPLATFORM - categories.CARRIER - categories.EXPERIMENTAL, unitPos, 400)
                if not table.empty(plats) then
                    local closest, distance
                    for k, v in plats do
                        if not v.Dead then
                            local roomAvailable = false
                            if not EntityCategoryContains(categories.CARRIER, v) then
                                roomAvailable = v:TransportHasSpaceFor(unit)
                            end
                            if roomAvailable and (not v.Refueling or table.getn(v.Refueling) < 6) then
                                local platPos = v:GetPosition()
                                local tempDist = VDist2(unitPos[1], unitPos[3], platPos[1], platPos[3])
                                if (not closest or tempDist < distance) then
                                    closest = v
                                    distance = tempDist
                                end
                            end
                        end
                    end
                    if closest then
                        local plat = aiBrain:MakePlatoon('', '')
                        aiBrain:AssignUnitsToPlatoon(plat, {unit}, 'Attack', 'None')
                        IssueStop({unit})
                        IssueClearCommands({unit})
                        IssueTransportLoad({unit}, closest)
                        if EntityCategoryContains(categories.AIRSTAGINGPLATFORM, closest) and not closest.AirStaging then
                            closest.AirStaging = closest:ForkThread(AirStagingThreadSorian)
                            closest.Refueling = {}
                        elseif EntityCategoryContains(categories.CARRIER, closest) and not closest.CarrierStaging then
                            closest.CarrierStaging = closest:ForkThread(CarrierStagingThread)
                            closest.Refueling = {}
                        end
                        table.insert(closest.Refueling, unit)
                        unit.Loading = true
                    end
                end
            end
        end
        WaitSeconds(1)
    end
end

---@param unit Unit
function AirStagingThreadSorian(unit)
    local aiBrain = unit:GetAIBrain()
    while not unit.Dead do
        local ready = true
        local numUnits = 0
        for _, v in unit.Refueling do
            if not v.Dead and (v:GetFuelRatio() < 0.9 or v:GetHealthPercent() < 0.9) then
                ready = false
            elseif not v.Dead then
                numUnits = numUnits + 1
            end
        end

        local cargo = unit:GetCargo()
        if ready and numUnits == 0 and not table.empty(cargo) then
            local pos = unit:GetPosition()
            IssueClearCommands({unit})
            IssueTransportUnload({unit}, {pos[1] + 5, pos[2], pos[3] + 5})
            for _, v in cargo do
                local plat
                if not v.PlanName then
                    plat = aiBrain:MakePlatoon('', 'AirHuntAI')
                else
                    plat = aiBrain:MakePlatoon('', v.PlanName)
                end

                if v.PlatoonData then
                    plat.PlatoonData = {}
                    plat.PlatoonData = v.PlatoonData
                end
                aiBrain:AssignUnitsToPlatoon(plat, {v}, 'Attack', 'GrowthFormation')
            end
        end
        if numUnits > 0 then
            WaitSeconds(2)
            for k, v in unit.Refueling do
                if not v.Dead and not v:IsUnitState('Attached') and (v:GetFuelRatio() < .9 or v:GetHealthPercent() < .9) then
                    v.Loading = false
                    local plat
                    if not v.PlanName then
                        plat = aiBrain:MakePlatoon('', 'AirHuntAI')
                    else
                        plat = aiBrain:MakePlatoon('', v.PlanName)
                    end

                    if v.PlatoonData then
                        plat.PlatoonData = {}
                        plat.PlatoonData = v.PlatoonData
                    end
                    aiBrain:AssignUnitsToPlatoon(plat, {v}, 'Attack', 'GrowthFormation')
                    unit.Refueling[k] = nil
                end
            end
        end
        WaitSeconds(10)
    end
end

---@param aiBrain AIBrain
function NukeCheck(aiBrain)
    local Nukes
    local lastNukes = 0
    local waitcount = 0
    local rollcount = 0
    local nukeCount = 0
    local mapSizeX, mapSizeZ = GetMapSize()
    local size = mapSizeX

    if mapSizeZ > mapSizeX then
        size = mapSizeZ
    end

    local sizeDiag = math.sqrt((size * size) * 2)
    local nukeWait = math.max((sizeDiag / 40), 10)
    local numNukes = aiBrain:GetCurrentUnits(categories.NUKE * categories.SILO * categories.STRUCTURE * categories.TECH3)

    while true do
        lastNukes = numNukes
        repeat
            WaitSeconds(nukeWait)
            waitcount = 0
            nukeCount = 0
            numNukes = aiBrain:GetCurrentUnits(categories.NUKE * categories.SILO * categories.STRUCTURE * categories.TECH3)
            Nukes = aiBrain:GetListOfUnits(categories.NUKE * categories.SILO * categories.STRUCTURE * categories.TECH3, true)
            for _, v in Nukes do
                if v:GetWorkProgress() * 100 > waitcount then
                    waitcount = v:GetWorkProgress() * 100
                end
                if v:GetNukeSiloAmmoCount() > 0 then
                    nukeCount = nukeCount + 1
                end
            end
            if nukeCount > 0 and lastNukes > 0 then
                WaitSeconds(5)

                SUtils.Nuke(aiBrain)
                rollcount = 0
                WaitSeconds(30)
            end
        until numNukes > lastNukes and waitcount < 65 and rollcount < 2

        Nukes = aiBrain:GetListOfUnits(categories.NUKE * categories.SILO * categories.STRUCTURE * categories.TECH3, true)
        rollcount = rollcount + (numNukes - lastNukes)

        for _, v in Nukes do
            IssueStop({v})
        end
        WaitSeconds(5)

        for _, v in Nukes do
            v:SetAutoMode(true)
        end
    end
end

---@param platoon Platoon
function AirLandToggleSorian(platoon)
    for _, v in platoon:GetPlatoonUnits() do
        if not v.Dead and not v.AirLandToggleThreadSorian then
            v.AirLandToggleThreadSorian = v:ForkThread(AirLandToggleThreadSorian)
        end
    end
end

---@param unit Unit
function AirLandToggleThreadSorian(unit)

    local bp = unit:GetBlueprint()
    local weapons = bp.Weapon
    local antiAirRange
    local landRange
    local unitCat = ParseEntityCategory(unit.UnitId)
    for _, v in weapons do
        if v.ToggleWeapon then
            local weaponType = 'Land'
            for n, wType in v.FireTargetLayerCapsTable do
                if string.find(wType, 'Air') then
                    weaponType = 'Air'
                    break
                end
            end
            if weaponType == 'Land' then
                landRange = v.MaxRadius
            else
                antiAirRange = v.MaxRadius
            end
        end
    end

    if not landRange or not antiAirRange then
        return
    end

    local aiBrain = unit:GetAIBrain()
    while not unit.Dead do
        local position = unit:GetPosition()
        local numAir = aiBrain:GetNumUnitsAroundPoint((categories.MOBILE * categories.AIR) - unitCat , position, antiAirRange, 'Enemy')
        local numGround = aiBrain:GetNumUnitsAroundPoint((categories.LAND + categories.NAVAL + categories.STRUCTURE) - unitCat, position, landRange, 'Enemy')
        local frndAir = aiBrain:GetNumUnitsAroundPoint((categories.MOBILE * categories.AIR) - unitCat, position, antiAirRange, 'Ally')
        local frndGround = aiBrain:GetNumUnitsAroundPoint((categories.LAND + categories.NAVAL + categories.STRUCTURE) - unitCat, position, landRange, 'Ally')
        if numAir > 5 and frndAir < 3 then
            unit:SetScriptBit('RULEUTC_WeaponToggle', false)
        elseif numGround > (numAir * 1.5) then
            unit:SetScriptBit('RULEUTC_WeaponToggle', true)
        elseif frndAir > frndGround then
            unit:SetScriptBit('RULEUTC_WeaponToggle', true)
        else
            unit:SetScriptBit('RULEUTC_WeaponToggle', false)
        end
        WaitSeconds(10)
    end
end