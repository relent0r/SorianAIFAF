local SBC = import("/mods/sorianaifaf/lua/editor/sorianbuildconditions.lua")
local SUtils = import("/lua/ai/sorianutilities.lua")

---@param platoon Platoon
function CommanderBehaviorSorian(platoon)
    for _, v in platoon:GetPlatoonUnits() do
        if not v.Dead and not v.CommanderThread then
            v.CommanderThread = v:ForkThread(CommanderThreadSorian, platoon)
        end
    end
end

---@param cdr CommandUnit
---@param platoon Platoon
function CommanderThreadSorian(cdr, platoon)
    if platoon.PlatoonData.aggroCDR then
        local mapSizeX, mapSizeZ = GetMapSize()
        local size = mapSizeX
        if mapSizeZ > mapSizeX then
            size = mapSizeZ
        end
        cdr.Mult = (size / 2) / 100
    end

    SetCDRHome(cdr, platoon)

    local aiBrain = cdr:GetAIBrain()
    aiBrain:BuildScoutLocationsSorian()
    if not SUtils.CheckForMapMarkers(aiBrain) then
        SUtils.AISendChat('all', ArmyBrains[aiBrain:GetArmyIndex()].Nickname, 'badmap')
    end

    moveOnNext = false
    moveWait = 0
    local Mult = cdr.Mult or 1
    local Delay = platoon.PlatoonData.Delay or 165
    local WaitTaunt = 600 + Random(1, 600)
    while not cdr.Dead do
        if Mult > 1 and (SBC.GreaterThanGameTime(aiBrain, 1200) or not SBC.EnemyToAllyRatioLessOrEqual(aiBrain, 1.0) or not SBC.ClosestEnemyLessThan(aiBrain, 750) or not SUtils.CheckForMapMarkers(aiBrain)) then
            Mult = 1
        end
        WaitTicks(1)

        -- Overcharge
        if Mult == 1 and not cdr.Dead and not cdr.Upgrading and SBC.GreaterThanGameTime(aiBrain, Delay) and
        UCBC.HaveGreaterThanUnitsWithCategory(aiBrain,  1, 'FACTORY') and aiBrain:GetNoRushTicks() <= 0 then
            CDROverChargeSorian(aiBrain, cdr)
        end
        WaitTicks(1)

        -- Run Away
        if not cdr.Dead then CDRRunAwaySorian(aiBrain, cdr) end
        WaitTicks(1)

        -- Go back to base
        if not cdr.Dead then CDRReturnHomeSorian(aiBrain, cdr, Mult) end
        WaitTicks(1)

        if not cdr.Dead and cdr:IsIdleState() and moveOnNext then
            CDRHideBehavior(aiBrain, cdr)
            moveOnNext = false
        end
        WaitTicks(1)

        if not cdr.Dead and cdr:IsIdleState() and not cdr.GoingHome and not cdr.Fighting and not cdr.Upgrading and not cdr:IsUnitState("Building")
        and not cdr:IsUnitState("Attacking") and not cdr:IsUnitState("Repairing") and not cdr.UnitBeingBuiltBehavior and not cdr:IsUnitState("Upgrading")
        and not cdr:IsUnitState("Enhancing") and not moveOnNext then
            moveWait = moveWait + 1
            if moveWait >= 10 then
                moveWait = 0
                moveOnNext = true
            end
        else
            moveWait = 0
        end
        WaitTicks(1)

        -- Call platoon resume building deal...
        if not cdr.Dead and cdr:IsIdleState() and not cdr.GoingHome and not cdr.Fighting and not cdr.Upgrading and not cdr:IsUnitState("Building")
        and not cdr:IsUnitState("Attacking") and not cdr:IsUnitState("Repairing") and not cdr.UnitBeingBuiltBehavior and not cdr:IsUnitState("Upgrading")
        and not cdr:IsUnitState("Enhancing") and not (SUtils.XZDistanceTwoVectorsSq(cdr.CDRHome, cdr:GetPosition()) > 100)
        and not cdr:IsUnitState('BlockCommandQueue') then
            if not cdr.EngineerBuildQueue or table.empty(cdr.EngineerBuildQueue) then
                local pool = aiBrain:GetPlatoonUniquelyNamed('ArmyPool')
                aiBrain:AssignUnitsToPlatoon(pool, {cdr}, 'Unassigned', 'None')
            elseif cdr.EngineerBuildQueue and not table.empty(cdr.EngineerBuildQueue) then
                if not cdr.NotBuildingThread then
                    cdr.NotBuildingThread = cdr:ForkThread(platoon.WatchForNotBuildingSorian)
                end
            end
        end
        WaitSeconds(1)

        if not cdr.Dead and GetGameTimeSeconds() > WaitTaunt and (not aiBrain.LastVocTaunt or GetGameTimeSeconds() - aiBrain.LastVocTaunt > WaitTaunt) then
            SUtils.AIRandomizeTaunt(aiBrain)
            WaitTaunt = 600 + Random(1, 900)
        end
    end
end

---@param aiBrain AIBrain
---@param cdr CommandUnit
function CDRRunAwaySorian(aiBrain, cdr)
    local shieldPercent
    local cdrPos = cdr:GetPosition()

    cdr.UnitBeingBuiltBehavior = false

    if (cdr:HasEnhancement('Shield') or cdr:HasEnhancement('ShieldGeneratorField') or cdr:HasEnhancement('ShieldHeavy')) and cdr:ShieldIsOn() then
        shieldPercent = (cdr.MyShield:GetHealth() / cdr.MyShield:GetMaxHealth())
    else
        shieldPercent = 1
    end

    local nmeHardcore = aiBrain:GetNumUnitsAroundPoint(categories.EXPERIMENTAL, cdrPos, 130, 'Enemy')
    local nmeT3 = aiBrain:GetNumUnitsAroundPoint(categories.LAND * categories.TECH3 - categories.ENGINEER, cdrPos, 50, 'Enemy')
    if cdr:GetHealthPercent() < 0.7 or shieldPercent < 0.3 or nmeHardcore > 0 or nmeT3 > 4 then
        local nmeAir = aiBrain:GetNumUnitsAroundPoint(categories.AIR - categories.SCOUT - categories.INTELLIGENCE, cdrPos, 30, 'Enemy')
        local nmeLand = aiBrain:GetNumUnitsAroundPoint(categories.COMMAND + categories.LAND - categories.ENGINEER - categories.SCOUT - categories.TECH1, cdrPos, 40, 'Enemy')
        local nmaShield = aiBrain:GetNumUnitsAroundPoint(categories.SHIELD * categories.STRUCTURE, cdrPos, 100, 'Ally')
        if nmeAir > 4 or nmeLand > 9 or nmeT3 > 4 or nmeHardcore > 0 or cdr:GetHealthPercent() < 0.7 or shieldPercent < 0.3 then
            if cdr.UnitBeingBuilt then
                cdr.UnitBeingBuiltBehavior = cdr.UnitBeingBuilt
            end

            cdr.GoingHome = true
            cdr.Fighting = false
            cdr.Upgrading = false

            if cdr.PlatoonHandle then
                cdr.PlatoonHandle:PlatoonDisband()
            end

            aiBrain.BaseMonitor.CDRDistress = cdrPos
            aiBrain.BaseMonitor.CDRThreatLevel = aiBrain:GetThreatAtPosition(cdrPos, 1, true, 'AntiSurface')

            CDRRevertPriorityChange(aiBrain, cdr)

            local runShield = false
            local category
            if nmaShield > 0 then
                category = categories.SHIELD * categories.STRUCTURE
                runShield = true
            elseif nmeAir > 3 then
                category = categories.DEFENSE * categories.ANTIAIR
            else
                category = categories.DEFENSE * categories.DIRECTFIRE
            end

            local runSpot, prevSpot
            local plat = aiBrain:MakePlatoon('', '')
            local canTeleport = false
            aiBrain:AssignUnitsToPlatoon(plat, {cdr}, 'support', 'None')
            repeat
                if not aiBrain:PlatoonExists(plat) then
                    return
                end

                if canTeleport then
                    runSpot = AIUtils.AIFindDefensiveAreaSorian(aiBrain, cdr, category, 10000, runShield)
                else
                    runSpot = AIUtils.AIFindDefensiveAreaSorian(aiBrain, cdr, category, 100, runShield)
                end

                if not runSpot then
                    local x, z = aiBrain:GetArmyStartPos()
                    runSpot = AIUtils.RandomLocation(x, z)
                end

                if not prevSpot or runSpot[1] ~= prevSpot[1] or runSpot[3] ~= prevSpot[3] then
                    IssueClearCommands({cdr})
                    if VDist2(cdrPos[1], cdrPos[3], runSpot[1], runSpot[3]) >= 10 then
                        if canTeleport then
                            IssueTeleport({cdr}, runSpot)
                        else
                            IssueMove({cdr}, runSpot)
                        end
                    end
                end
                WaitSeconds(3)

                if not cdr.Dead then
                    cdrPos = cdr:GetPosition()
                    nmeAir = aiBrain:GetNumUnitsAroundPoint(categories.AIR - categories.SCOUT - categories.INTELLIGENCE, cdrPos, 30, 'Enemy')
                    nmeLand = aiBrain:GetNumUnitsAroundPoint(categories.COMMAND + categories.LAND - categories.ENGINEER - categories.SCOUT - categories.TECH1, cdrPos, 40, 'Enemy')
                    nmeT3 = aiBrain:GetNumUnitsAroundPoint(categories.LAND * categories.TECH3 - categories.ENGINEER, cdrPos, 50, 'Enemy')
                    nmeHardcore = aiBrain:GetNumUnitsAroundPoint(categories.EXPERIMENTAL, cdrPos, 130, 'Enemy')
                    if (cdr:HasEnhancement('Shield') or cdr:HasEnhancement('ShieldGeneratorField') or cdr:HasEnhancement('ShieldHeavy')) and cdr:ShieldIsOn() then
                        shieldPercent = (cdr.MyShield:GetHealth() / cdr.MyShield:GetMaxHealth())
                    else
                        shieldPercent = 1
                    end
                end
            until cdr.Dead or (cdr:GetHealthPercent() > 0.75 and shieldPercent > 0.35 and nmeAir < 5 and nmeLand < 10 and nmeHardcore == 0 and nmeT3 < 5)

            cdr.GoingHome = false
            IssueClearCommands({cdr})
            aiBrain.BaseMonitor.CDRDistress = false
            aiBrain.BaseMonitor.CDRThreatLevel = 0
            if cdr.UnitBeingBuiltBehavior then
                cdr:ForkThread(CDRFinishUnit)
            end
        end
    end
end

---@param aiBrain AIBrain
---@param cdr CommandUnit
function CDROverChargeSorian(aiBrain, cdr)
    local weapBPs = cdr:GetBlueprint().Weapon
    local weapon
    for k, v in weapBPs do
        if v.Label == 'OverCharge' then
            weapon = v
            break
        end
    end

    local distressRange = 100
    local maxRadius = weapon.MaxRadius * 4.55
    local weapRange = weapon.MaxRadius
    cdr.UnitBeingBuiltBehavior = false

    local cdrPos = cdr.CDRHome
    local numUnits1 = aiBrain:GetNumUnitsAroundPoint(categories.LAND * categories.TECH1 - categories.SCOUT - categories.ENGINEER, cdrPos, maxRadius, 'Enemy')
    local numUnits2 = aiBrain:GetNumUnitsAroundPoint(categories.LAND * categories.TECH2 - categories.SCOUT - categories.ENGINEER, cdrPos, maxRadius, 'Enemy')
    local numUnits3 = aiBrain:GetNumUnitsAroundPoint(categories.LAND * categories.TECH3 - categories.SCOUT - categories.ENGINEER, cdrPos, maxRadius, 'Enemy')
    local numUnitsEng = aiBrain:GetNumUnitsAroundPoint(categories.ENGINEER * (categories.TECH1 + categories.TECH2 + categories.TECH3), cdrPos, maxRadius, 'Enemy')
    local numUnits4 = aiBrain:GetNumUnitsAroundPoint(categories.EXPERIMENTAL, cdrPos, maxRadius + 130, 'Enemy')
    local numStructs = aiBrain:GetNumUnitsAroundPoint(categories.STRUCTURE, cdrPos, maxRadius, 'Enemy')
    local numUnitsDF = aiBrain:GetNumUnitsAroundPoint(categories.DEFENSE * categories.STRUCTURE * categories.DIRECTFIRE - categories.TECH1, cdrPos, maxRadius + 50, 'Enemy')
    local numUnitsDF1 = aiBrain:GetNumUnitsAroundPoint(categories.DEFENSE * categories.STRUCTURE * categories.DIRECTFIRE * categories.TECH1, cdrPos, maxRadius + 30, 'Enemy')
    local numUnitsIF = aiBrain:GetNumUnitsAroundPoint(categories.DEFENSE * categories.STRUCTURE * categories.INDIRECTFIRE - categories.TECH1, cdrPos, maxRadius + 260, 'Enemy')
    local totalUnits = numUnits1 + numUnits2 + numUnits3 + numUnits4 + numStructs + numUnitsEng
    local distressLoc = aiBrain:BaseMonitorDistressLocation(cdrPos)

    if (cdr:HasEnhancement('Shield') or cdr:HasEnhancement('ShieldGeneratorField') or cdr:HasEnhancement('ShieldHeavy')) and cdr:ShieldIsOn() then
        shieldPercent = (cdr.MyShield:GetHealth() / cdr.MyShield:GetMaxHealth())
    else
        shieldPercent = 1
    end



    if Utilities.XZDistanceTwoVectors(cdrPos, cdr:GetPosition()) > distressRange then
        return
    end

    local commanderResponse = false
    if distressLoc then
        local distressUnitsNaval = aiBrain:GetNumUnitsAroundPoint(categories.NAVAL, distressLoc, 40, 'Enemy')
        local distressUnitsAir = aiBrain:GetNumUnitsAroundPoint(categories.AIR * (categories.BOMBER + categories.GROUNDATTACK + categories.ANTINAVY), distressLoc, 30, 'Enemy')
        local distressUnitsexp = aiBrain:GetNumUnitsAroundPoint(categories.EXPERIMENTAL, distressLoc, 50, 'Enemy')
        if distressUnitsNaval > 0 then
            if cdr:HasEnhancement('NaniteTorpedoTube') and distressUnitsNaval < 5 and distressUnitsexp < 1 then
                commanderResponse = true
            else
                commanderResponse = false
            end
        elseif distressUnitsAir > 0 then
            commanderResponse = false
        elseif distressUnitsexp > 0 then
            commanderResponse = false
        elseif numUnits1 > 14 or numUnits2 > 9 or numUnits3 > 4 or numUnits4 > 0 or numUnitsDF > 0 or numUnitsIF > 0 or numUnitsDF1 > 2 then
            commanderResponse = false
        else
            commanderResponse = true
        end
    end

    local overCharging = false
    if (cdr:GetHealthPercent() > 0.85 and shieldPercent > 0.35) and ((totalUnits > 0 and numUnits1 < 15 and numUnits2 < 10 and numUnits3 < 5 and numUnits4 < 1 and numUnitsDF1 < 3 and numUnitsDF < 1 and numUnitsIF < 1) or (not cdr.DistressCall and distressLoc and commanderResponse and Utilities.XZDistanceTwoVectors(distressLoc, cdrPos) < distressRange)) then
        CDRRevertPriorityChange(aiBrain, cdr)
        if cdr.UnitBeingBuilt then
            cdr.UnitBeingBuiltBehavior = cdr.UnitBeingBuilt
        end

        cdr.Fighting = true
        cdr.GoingHome = false
        cdr.Upgrading = false
        local plat = aiBrain:MakePlatoon('', '')
        aiBrain:AssignUnitsToPlatoon(plat, {cdr}, 'support', 'None')
        plat:Stop()

        local priList = {categories.ENERGYPRODUCTION * categories.STRUCTURE * categories.DRAGBUILD, categories.TECH3 * categories.INDIRECTFIRE,
            categories.TECH3 * categories.MOBILE, categories.TECH2 * categories.INDIRECTFIRE, categories.MOBILE * categories.TECH2,
            categories.TECH1 * categories.INDIRECTFIRE, categories.TECH1 * categories.MOBILE, categories.CONSTRUCTION * categories.STRUCTURE, categories.ECONOMIC * categories.STRUCTURE, categories.ALLUNITS}
        plat:SetPrioritizedTargetList('support', priList)
        cdr:SetTargetPriorities(priList)

        local target
        local continueFighting = true
        local counter = 0
        local cdrThreat = cdr:GetBlueprint().Defense.SurfaceThreatLevel or 60
        local enemyThreat
        repeat
            overCharging = false
            local cdrCurrentPos = cdr:GetPosition()
            if counter >= 5 or not target or target.Dead or Utilities.XZDistanceTwoVectors(cdrPos, target:GetPosition()) > maxRadius then
                counter = 0
                for _, v in priList do
                    target = plat:FindClosestUnit('Support', 'Enemy', true, v)
                    if target and Utilities.XZDistanceTwoVectors(cdrPos, target:GetPosition()) < maxRadius then
                        local cdrLayer = cdr.Layer
                        local targetLayer = target.Layer
                        if not (cdrLayer == 'Land' and (targetLayer == 'Air' or targetLayer == 'Sub' or targetLayer == 'Seabed')) and
                           not (cdrLayer == 'Seabed' and (targetLayer == 'Air' or targetLayer == 'Water')) then
                            break
                        end
                    end
                    target = false
                end
                if target then
                    local targetPos = target:GetPosition()
                    enemyThreat = aiBrain:GetThreatAtPosition(targetPos, 1, true, 'AntiSurface')
                    enemyCdrThreat = aiBrain:GetThreatAtPosition(targetPos, 1, true, 'Commander')
                    friendlyThreat = aiBrain:GetThreatAtPosition(targetPos, 1, true, 'AntiSurface', aiBrain:GetArmyIndex())
                    if enemyThreat - enemyCdrThreat >= friendlyThreat + cdrThreat then
                        return
                    end
                    if aiBrain:GetEconomyStored('ENERGY') >= weapon.EnergyRequired and target and not target.Dead and Utilities.XZDistanceTwoVectors(cdrCurrentPos, target:GetPosition()) <= weapRange then
                        overCharging = true
                        IssueClearCommands({cdr})
                        IssueOverCharge({cdr}, target)
                    elseif target and not target.Dead then
                        local tarPos = target:GetPosition()
                        IssueClearCommands({cdr})
                        IssueMove({cdr}, tarPos)
                        IssueMove({cdr}, cdr.CDRHome)
                    end
                elseif distressLoc then
                    enemyThreat = aiBrain:GetThreatAtPosition(distressLoc, 1, true, 'AntiSurface')
                    enemyCdrThreat = aiBrain:GetThreatAtPosition(distressLoc, 1, true, 'Commander')
                    friendlyThreat = aiBrain:GetThreatAtPosition(distressLoc, 1, true, 'AntiSurface', aiBrain:GetArmyIndex())
                    if enemyThreat - enemyCdrThreat >= friendlyThreat + (cdrThreat / 1.5) then
                        return
                    end
                    if distressLoc and (Utilities.XZDistanceTwoVectors(distressLoc, cdrPos) < distressRange) then
                        IssueClearCommands({cdr})
                        IssueMove({cdr}, distressLoc)
                        IssueMove({cdr}, cdr.CDRHome)
                    end
                end
            end
            if overCharging then
                while target and not target.Dead and not cdr.Dead and counter <= 5 do
                    WaitSeconds(0.5)
                    counter = counter + 0.5
                end
            else
                WaitSeconds(5)
                counter = counter + 5
            end

            distressLoc = aiBrain:BaseMonitorDistressLocation(cdrPos)
            if cdr.Dead then
                return
            end

            if (cdr:HasEnhancement('Shield') or cdr:HasEnhancement('ShieldGeneratorField') or cdr:HasEnhancement('ShieldHeavy')) and cdr:ShieldIsOn() then
                shieldPercent = (cdr.MyShield:GetHealth() / cdr.MyShield:GetMaxHealth())
            else
                shieldPercent = 1
            end

            enemyThreat = aiBrain:GetThreatAtPosition(cdrPos, 1, true, 'AntiSurface')
            enemyCdrThreat = aiBrain:GetThreatAtPosition(cdrPos, 1, true, 'Commander')
            friendlyThreat = aiBrain:GetThreatAtPosition(cdrPos, 1, true, 'AntiSurface', aiBrain:GetArmyIndex())
            if ((aiBrain:GetNumUnitsAroundPoint(categories.LAND - categories.SCOUT, cdrPos, maxRadius, 'Enemy') == 0)
                and (not distressLoc or (Utilities.XZDistanceTwoVectors(distressLoc, cdrPos) > distressRange)
                and (Utilities.XZDistanceTwoVectors(cdr.CDRHome, cdr:GetPosition()) < maxRadius))) or enemyThreat - enemyCdrThreat >= friendlyThreat + (cdrThreat / 1.5) or (aiBrain:GetNumUnitsAroundPoint(categories.LAND - categories.SCOUT, cdrPos, maxRadius, 'Enemy')) >= 15 or (cdr:GetHealthPercent() < .80 or shieldPercent < .30) then
                continueFighting = false
            end
        until not continueFighting or not aiBrain:PlatoonExists(plat)

        cdr.Fighting = false
        IssueClearCommands({cdr})
        if overCharging then
            IssueMove({cdr}, cdr.CDRHome)
        end

        if cdr.UnitBeingBuiltBehavior then
            cdr:ForkThread(CDRFinishUnit)
        end
    end
end

---@param aiBrain AIBrain
---@param cdr CommandUnit
---@param Mult number
function CDRReturnHomeSorian(aiBrain, cdr, Mult)
    -- This is a reference... so it will autoupdate
    local cdrPos = cdr:GetPosition()
    local rad = 100 * Mult
    local distSqAway = rad * rad
    local loc = cdr.CDRHome
    if not cdr.Dead and VDist2Sq(cdrPos[1], cdrPos[3], loc[1], loc[3]) > distSqAway then
        local plat = aiBrain:MakePlatoon('', '')
        aiBrain:AssignUnitsToPlatoon(plat, {cdr}, 'support', 'None')
        IssueClearCommands({cdr})

        repeat
            CDRRevertPriorityChange(aiBrain, cdr)
            cdr.GoingHome = true
            cdr.Fighting = false
            cdr.Upgrading = false
            if not aiBrain:PlatoonExists(plat) then
                return
            end
            IssueMove({cdr}, loc)
            WaitSeconds(7)
            cdrPos = cdr:GetPosition()
        until cdr.Dead or VDist2Sq(cdrPos[1], cdrPos[3], loc[1], loc[3]) <= (rad / 2) * (rad / 2)

        cdr.GoingHome = false
        IssueClearCommands({cdr})
    end
end

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

---@param self any
function ScathisBehaviorSorian(self)
    local aiBrain = self:GetBrain()

    AssignExperimentalPrioritiesSorian(self)

    -- Find target loop
    local experimental
    local targetUnit = false
    local lastBase = false
    local airUnit = false
    local platoonUnits = self:GetPlatoonUnits()
    while aiBrain:PlatoonExists(self) do
        if lastBase then
            targetUnit, lastBase = WreckBaseSorian(self, lastBase)
        end

        if not lastBase then
            targetUnit, lastBase = FindExperimentalTargetSorian(self)
        end

        if targetUnit then
            IssueClearCommands(platoonUnits)
            IssueAggressiveMove(platoonUnits, targetUnit:GetPosition())
        end

        -- Walk to and kill target loop
        while aiBrain:PlatoonExists(self) and targetUnit and not targetUnit.Dead do
            local nearCommander = CommanderOverrideCheckSorian(self)
            if nearCommander and nearCommander ~= targetUnit then
                IssueClearCommands(platoonUnits)
                IssueAggressiveMove(platoonUnits, nearCommander:GetPosition())
                targetUnit = nearCommander
            end

            -- Check if we or the target are under a shield
            local closestBlockingShield = false
            for k, v in platoonUnits do
                if not v.Dead then
                    experimental = v
                    break
                end
            end

            if not airUnit then
                closestBlockingShield = GetClosestShieldProtectingTargetSorian(experimental, experimental)
            end
            closestBlockingShield = closestBlockingShield or GetClosestShieldProtectingTargetSorian(experimental, targetUnit)

            -- Kill shields loop
            while closestBlockingShield do
                IssueClearCommands({experimental})
                IssueAggressiveMove({experimental}, closestBlockingShield:GetPosition())

                -- Wait for shield to die loop
                while not closestBlockingShield.Dead and aiBrain:PlatoonExists(self) do
                    self:MergeWithNearbyPlatoonsSorian('ExperimentalAIHubSorian', 50, true)
                    WaitSeconds(1)
                end

                closestBlockingShield = false
                for k, v in platoonUnits do
                    if not v.Dead then
                        experimental = v
                        break
                    end
                end
                if not airUnit then
                    closestBlockingShield = GetClosestShieldProtectingTargetSorian(experimental, experimental)
                end
                closestBlockingShield = closestBlockingShield or GetClosestShieldProtectingTargetSorian(experimental, targetUnit)
                WaitSeconds(1)
            end
            WaitSeconds(1)
        end
        WaitSeconds(1)
    end
end

---@param self any
function FatBoyBehaviorSorian(self)
    if not self:GatherUnitsSorian() then
        return
    end

    AssignExperimentalPrioritiesSorian(self)

    -- Find target loop
    local experimental
    local targetUnit = false
    local lastBase = false
    local airUnit = false
    local useMove = true
    local aiBrain = self:GetBrain()
    local platoonUnits = self:GetPlatoonUnits()
    local cmd
    while aiBrain:PlatoonExists(self) do
        self:MergeWithNearbyPlatoonsSorian('ExperimentalAIHubSorian', 50, true)
        if lastBase then
            targetUnit, lastBase = WreckBaseSorian(self, lastBase)
        end

        if not lastBase then
            targetUnit, lastBase = FindExperimentalTargetSorian(self)
        end

        useMove = InWaterCheck(self)
        if targetUnit then
            IssueClearCommands(platoonUnits)
            if useMove then
                cmd = ExpPathToLocation(aiBrain, self, 'Amphibious', targetUnit:GetPosition(), false)
            else
                cmd = ExpPathToLocation(aiBrain, self, 'Amphibious', targetUnit:GetPosition(), 'AttackMove')
            end
        else
            --LOG('*DEBUG: FatBoy no target.')
        end

        -- Walk to and kill target loop
        while aiBrain:PlatoonExists(self) and targetUnit and not targetUnit.Dead and useMove == InWaterCheck(self) and self:IsCommandsActive(cmd) do
            self:MergeWithNearbyPlatoonsSorian('ExperimentalAIHubSorian', 50, true)
            useMove = InWaterCheck(self)
            local nearCommander = CommanderOverrideCheckSorian(self)
            if nearCommander and nearCommander ~= targetUnit then
                IssueClearCommands(platoonUnits)
                if useMove then
                    cmd = ExpPathToLocation(aiBrain, self, 'Amphibious', nearCommander:GetPosition(), false)
                else
                    cmd = self:AttackTarget(targetUnit)
                end
                targetUnit = nearCommander
            end

            -- Check if we or the target are under a shield
            local closestBlockingShield = false
            for k, v in platoonUnits do
                if not v.Dead then
                    experimental = v
                    break
                end
            end

            if not airUnit then
                closestBlockingShield = GetClosestShieldProtectingTargetSorian(experimental, experimental)
            end
            closestBlockingShield = closestBlockingShield or GetClosestShieldProtectingTargetSorian(experimental, targetUnit)

            -- Kill shields loop
            local oldTarget = false
            while closestBlockingShield do
                oldTarget = oldTarget or targetUnit
                targetUnit = false
                self:MergeWithNearbyPlatoonsSorian('ExperimentalAIHubSorian', 50, true)
                useMove = InWaterCheck(self)
                IssueClearCommands(platoonUnits)
                if useMove then
                    cmd = ExpPathToLocation(aiBrain, self, 'Amphibious', closestBlockingShield:GetPosition(), false)
                else
                    cmd = ExpPathToLocation(aiBrain, self, 'Amphibious', closestBlockingShield:GetPosition(), 'AttackMove')
                end

                -- Wait for shield to die loop
                while not closestBlockingShield.Dead and aiBrain:PlatoonExists(self) and useMove == InWaterCheck(self) and self:IsCommandsActive(cmd) do
                    self:MergeWithNearbyPlatoonsSorian('ExperimentalAIHubSorian', 50, true)
                    useMove = InWaterCheck(self)
                    WaitSeconds(1)
                end

                closestBlockingShield = false
                for k, v in platoonUnits do
                    if not v.Dead then
                        experimental = v
                        break
                    end
                end

                if not airUnit then
                    closestBlockingShield = GetClosestShieldProtectingTargetSorian(experimental, experimental)
                end
                closestBlockingShield = closestBlockingShield or GetClosestShieldProtectingTargetSorian(experimental, oldTarget)
                WaitSeconds(1)
            end
            WaitSeconds(1)
        end
        WaitSeconds(1)
    end
end

---@param self any
function BehemothBehaviorSorian(self)
    if not self:GatherUnitsSorian() then
        return
    end
    AssignExperimentalPrioritiesSorian(self)

    -- Find target loop
    local experimental
    local targetUnit = false
    local lastBase = false
    local airUnit = false
    local useMove = true
    local farTarget = false
    local aiBrain = self:GetBrain()
    local platoonUnits = self:GetPlatoonUnits()
    local cmd
    while aiBrain:PlatoonExists(self) do
        self:MergeWithNearbyPlatoonsSorian('ExperimentalAIHubSorian', 50, true)
        useMove = InWaterCheck(self)
        if lastBase then
            targetUnit, lastBase = WreckBaseSorian(self, lastBase)
        end

        if not lastBase then
            targetUnit, lastBase = FindExperimentalTargetSorian(self)
        end

        farTarget = false
        if targetUnit and SUtils.XZDistanceTwoVectorsSq(self:GetPlatoonPosition(), targetUnit:GetPosition()) >= 40000 then
            farTarget = true
        end

        if targetUnit then
            IssueClearCommands(platoonUnits)
            if useMove or not farTarget then
                cmd = ExpPathToLocation(aiBrain, self, 'Amphibious', targetUnit:GetPosition(), false)
            else
                cmd = ExpPathToLocation(aiBrain, self, 'Amphibious', targetUnit:GetPosition(), 'AttackMove')
            end
        end

        -- Walk to and kill target loop
        local nearCommander = CommanderOverrideCheckSorian(self)
        local ACUattack = false
        while aiBrain:PlatoonExists(self) and targetUnit and not targetUnit.Dead and useMove == InWaterCheck(self) and
        self:IsCommandsActive(cmd) and (nearCommander or ((farTarget and SUtils.XZDistanceTwoVectorsSq(self:GetPlatoonPosition(), targetUnit:GetPosition()) >= 40000) or
        (not farTarget and SUtils.XZDistanceTwoVectorsSq(self:GetPlatoonPosition(), targetUnit:GetPosition()) < 40000))) do
            self:MergeWithNearbyPlatoonsSorian('ExperimentalAIHubSorian', 50, true)
            useMove = InWaterCheck(self)
            nearCommander = CommanderOverrideCheckSorian(self)

            if nearCommander and (nearCommander ~= targetUnit or
            (not ACUattack and SUtils.XZDistanceTwoVectorsSq(self:GetPlatoonPosition(), nearCommander:GetPosition()) < 40000)) then
                IssueClearCommands(platoonUnits)
                if useMove then
                    cmd = ExpPathToLocation(aiBrain, self, 'Amphibious', nearCommander:GetPosition(), false)
                else
                    cmd = self:AttackTarget(targetUnit)
                    ACUattack = true
                end
                targetUnit = nearCommander
            end

            -- Check if we or the target are under a shield
            local closestBlockingShield = false
            for k, v in platoonUnits do
                if not v.Dead then
                    experimental = v
                    break
                end
            end

            if not airUnit then
                closestBlockingShield = GetClosestShieldProtectingTargetSorian(experimental, experimental)
            end
            closestBlockingShield = closestBlockingShield or GetClosestShieldProtectingTargetSorian(experimental, targetUnit)

            -- Kill shields loop
            local oldTarget = false
            while closestBlockingShield do
                oldTarget = oldTarget or targetUnit
                targetUnit = false
                self:MergeWithNearbyPlatoonsSorian('ExperimentalAIHubSorian', 50, true)
                useMove = InWaterCheck(self)
                IssueClearCommands(platoonUnits)
                if useMove or SUtils.XZDistanceTwoVectorsSq(self:GetPlatoonPosition(), closestBlockingShield:GetPosition()) < 40000 then
                    cmd = ExpPathToLocation(aiBrain, self, 'Amphibious', closestBlockingShield:GetPosition(), false)
                else
                    cmd = ExpPathToLocation(aiBrain, self, 'Amphibious', closestBlockingShield:GetPosition(), 'AttackMove')
                end

                local farAway = true
                if SUtils.XZDistanceTwoVectorsSq(self:GetPlatoonPosition(), closestBlockingShield:GetPosition()) < 40000 then
                    farAway = false
                end

                -- Wait for shield to die loop
                while not closestBlockingShield.Dead and aiBrain:PlatoonExists(self) and useMove == InWaterCheck(self)
                and self:IsCommandsActive(cmd) do
                    self:MergeWithNearbyPlatoonsSorian('ExperimentalAIHubSorian', 50, true)
                    useMove = InWaterCheck(self)
                    local targDistSq = SUtils.XZDistanceTwoVectorsSq(self:GetPlatoonPosition(), closestBlockingShield:GetPosition())
                    if (farAway and targDistSq < 40000) or (not farAway and targDistSq >= 40000) then
                        break
                    end
                    WaitSeconds(1)
                end

                closestBlockingShield = false
                for k, v in platoonUnits do
                    if not v.Dead then
                        experimental = v
                        break
                    end
                end

                if not airUnit then
                    closestBlockingShield = GetClosestShieldProtectingTargetSorian(experimental, experimental)
                end
                closestBlockingShield = closestBlockingShield or GetClosestShieldProtectingTargetSorian(experimental, oldTarget)
                WaitSeconds(1)
            end
            WaitSeconds(1)
        end
        WaitSeconds(1)
    end
end

---@param self any
TickBehaviorSorian = function(self)
    local aiBrain = self:GetBrain()
    if not aiBrain:PlatoonExists(self) then
        return
    end

    if not self:GatherUnitsSorian() then
        return
    end

    AssignExperimentalPrioritiesSorian(self)
    local targetLocation = GetHighestThreatClusterLocationSorian(aiBrain, self)
    local oldTargetLocation = nil
    local platoonUnits = self:GetPlatoonUnits()
    local cmd
    while aiBrain:PlatoonExists(self) do
        self:MergeWithNearbyPlatoonsSorian('ExperimentalAIHubSorian', 50, true)
        if (targetLocation and targetLocation ~= oldTargetLocation) or not self:IsCommandsActive(cmd) then
            IssueClearCommands(platoonUnits)
            cmd = ExpPathToLocation(aiBrain, self, 'Air', targetLocation, false, 62500)
            WaitSeconds(25)
        end
        WaitSeconds(1)

        oldTargetLocation = targetLocation
        targetLocation = GetHighestThreatClusterLocationSorian(aiBrain, self)
    end
end

