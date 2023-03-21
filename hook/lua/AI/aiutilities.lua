local SUtils = import("/lua/ai/sorianutilities.lua")

---@param aiBrain AIBrain
---@param location Vector
---@param radius number
---@param layer Layer
---@return table
function GetBasePatrolPointsSorian(aiBrain, location, radius, layer)
    if type(location) == 'string' then
        if aiBrain.HasPlatoonList then
            for k, v in aiBrain.PBM.Locations do
                if v.LocationType == location then
                    radius = v.Radius
                    location = v.Location
                    break
                end
            end
        elseif aiBrain.BuilderManagers[location] then
            radius = aiBrain.BuilderManagers[location].FactoryManager.Radius
            location = aiBrain.BuilderManagers[location].FactoryManager:GetLocationCoords()
        end
        if not radius then
            error('*AI ERROR: Invalid locationType- '..location..' for army- '..aiBrain.Name, 2)
        end
    end
    if not location or not radius then
        error('*AI ERROR: Need location and radius or locationType for AIUtilities.GetBasePatrolPoints', 2)
    end

    if not layer then
        layer = 'Land'
    end

    local vecs = aiBrain:GetBaseVectors()
    local locList = {}
    for _, v in vecs do
        if LayerCheckPosition(v, layer) and VDist2(v[1], v[3], location[1], location[3]) < radius then
            table.insert(locList, v)
        end
    end
    local sortedList = {}
    local lastX = location[1]
    local lastZ = location[3]

    if table.empty(locList) then return {} end

    local num = table.getsize(locList)
    local startX, startZ = aiBrain:GetArmyStartPos()
    local tempdistance = false
    local edistance
    local closeX, closeZ
    -- Sort the locations from point to closest point, that way it  makes a nice patrol path
    for _, v in ArmyBrains do
        if IsEnemy(v:GetArmyIndex(), aiBrain:GetArmyIndex()) then
            local estartX, estartZ = v:GetArmyStartPos()
            local tempdistance = VDist2(startX, startZ, estartX, estartZ)
            if not edistance or tempdistance < edistance then
                edistance = tempdistance
                closeX = estartX
                closeZ = estartZ
            end
        end
    end
    for i = 1, num do
        local lowest
        local czX, czZ, pos, distance, key
        for k, v in locList do
            local x = v[1]
            local z = v[3]
            if i == 1 then
                distance = VDist2(closeX, closeZ, x, z)
            else
                distance = VDist2(lastX, lastZ, x, z)
            end
            if not lowest or distance < lowest then
                pos = v
                lowest = distance
                key = k
            end
        end
        if not pos then return {} end
        sortedList[i] = pos
        lastX = pos[1]
        lastZ = pos[3]
        table.remove(locList, key)
    end

    return sortedList
end

--- used by engineers to move to a safe location
---@param aiBrain AIBrain
---@param unit Unit
---@param destination Vector
---@return boolean
function EngineerMoveWithSafePathSorian(aiBrain, unit, destination)
    if not destination then
        return false
    end
    local NavUtils = import("/lua/sim/navutils.lua")

    local unitPos = unit:GetPosition()
    local result, bestPos = NavUtils.CanPathTo('Land', unitPos, destination)
    if not NavUtils.CanPathTo('Land', unitPos, destination) then
        result, bestPos = NavUtils.CanPathTo('Amphibious', unitPos, destination)
        if not result and not SUtils.CheckForMapMarkers(aiBrain) then
            result, bestPos = unit:CanPathTo(destination)
        end
    end

    local pos = unit:GetPosition()
    local bUsedTransports = false
    if not result or VDist2Sq(pos[1], pos[3], destination[1], destination[3]) > 65536 and unit.PlatoonHandle and not EntityCategoryContains(categories.COMMAND, unit) then
        -- If we can't path to our destination, we need, rather than want, transports
        local needTransports = not result
        -- If distance > 512
        if VDist2Sq(pos[1], pos[3], destination[1], destination[3]) > 262144 then
            needTransports = true
        end
        -- Skip the last move... we want to return and do a build
        bUsedTransports = AIAttackUtils.SendPlatoonWithTransportsSorian(aiBrain, unit.PlatoonHandle, destination, needTransports, true, needTransports)

        if bUsedTransports then
            return true
        end
    end

    -- If we're here, we haven't used transports and we can path to the destination
    if result then
        local path, reason = AIAttackUtils.PlatoonGenerateSafePathToSorian(aiBrain, 'Amphibious', unit:GetPosition(), destination, 10)
        if path then
            local pathSize = table.getn(path)
            -- Move to way points (but not to destination... leave that for the final command)
            for widx, waypointPath in path do
                if pathSize ~= widx then
                    IssueMove({unit}, waypointPath)
                end
            end
        end
        -- If there wasn't a *safe* path (but dest was pathable), then the last move would have been to go there directly
        -- so don't bother... the build/capture/reclaim command will take care of that after we return
        return true
    end

    return false
end

---@param aiBrain AIBrain
---@param eng Unit
---@param whatToBuild any
---@param pos Vector
---@return boolean
function EngineerTryRepairSorian(aiBrain, eng, whatToBuild, pos)
    if not pos then
        return false
    end

    local checkRange = 75
    if IsMex(whatToBuild) then
        checkRange = 1
    end

    local structureCat = ParseEntityCategory(whatToBuild)
    local checkUnits = aiBrain:GetUnitsAroundPoint(structureCat, pos, checkRange, 'Ally')
    if checkUnits and not table.empty(checkUnits) then
        for num, unit in checkUnits do
            if unit:IsBeingBuilt() then
                IssueRepair({eng}, unit)
                return true
            end
        end
    end

    return false
end

---@param aiBrain AIBrain
---@param platoon Platoon
---@param squad string
---@param maxRange number
---@param atkPri number
---@param avoidbases any
---@return boolean
function AIFindPingTargetInRangeSorian(aiBrain, platoon, squad, maxRange, atkPri, avoidbases)
    local position = platoon:GetPlatoonPosition()
    if not aiBrain or not position or not maxRange then
        return false
    end

    local AttackPositions = AIGetAttackPointsAroundLocation(aiBrain, position, maxRange)
    for x, z in AttackPositions do
        local targetUnits = aiBrain:GetUnitsAroundPoint(categories.ALLUNITS, z, 100, 'Enemy')
        for _, v in atkPri do
            local category = ParseEntityCategory(v)
            local retUnit = false
            local distance = false
            local targetShields = 9999
            for num, unit in targetUnits do
                if not unit.Dead and EntityCategoryContains(category, unit) and platoon:CanAttackTarget(squad, unit) then
                    local unitPos = unit:GetPosition()
                    if avoidbases then
                        for _, w in ArmyBrains do
                            if IsAlly(w:GetArmyIndex(), aiBrain:GetArmyIndex()) or (aiBrain:GetArmyIndex() == w:GetArmyIndex()) then
                                local estartX, estartZ = w:GetArmyStartPos()
                                if VDist2Sq(estartX, estartZ, unitPos[1], unitPos[3]) < 22500 then
                                    continue
                                end
                            end
                        end
                    end
                    local numShields = aiBrain:GetNumUnitsAroundPoint(categories.DEFENSE * categories.SHIELD * categories.STRUCTURE, unitPos, 50, 'Enemy')
                    if not retUnit or numShields < targetShields or (numShields == targetShields and Utils.XZDistanceTwoVectors(position, unitPos) < distance) then
                        retUnit = unit
                        distance = Utils.XZDistanceTwoVectors(position, unitPos)
                        targetShields = numShields
                    end
                end
            end
            if retUnit and targetShields > 0 then
                local platoonUnits = platoon:GetPlatoonUnits()
                for _, w in platoonUnits do
                    if not w.Dead then
                        unit = w
                        break
                    end
                end
                local closestBlockingShield = AIBehaviors.GetClosestShieldProtectingTargetSorian(unit, retUnit)
                if closestBlockingShield then
                    return closestBlockingShield
                end
            end
            if retUnit then
                return retUnit
            end
        end
    end

    return false
end

--- We use both Blank Marker that are army names as well as the new Large Expansion Area to determine big expansion bases
---@param aiBrain AIBrain
---@param locationType string
---@param radius number
---@param tMin number
---@param tMax number
---@param tRings number
---@param tType string
---@param eng Unit
---@return boolean
---@return string|unknown
function AIFindStartLocationNeedsEngineerSorian(aiBrain, locationType, radius, tMin, tMax, tRings, tType, eng)
    local pos = aiBrain:PBMGetLocationCoords(locationType)
    if not pos then
        return false
    end

    local validStartPos = {}
    local validPos = AIGetMarkersAroundLocation(aiBrain, 'Large Expansion Area', pos, radius, tMin, tMax, tRings, tType)
    local positions = AIGetMarkersAroundLocation(aiBrain, 'Blank Marker', pos, radius, tMin, tMax, tRings, tType)
    local startX, startZ = aiBrain:GetArmyStartPos()
    for _, v in positions do
        if string.sub(v.Name, 1, 5) == 'ARMY_' then
            if startX ~= v.Position[1] and startZ ~= v.Position[3] then
                table.insert(validStartPos, v)
            end
        end
    end

    local retPos, retName
    if eng then
        if not table.empty(validStartPos) then
            retPos, retName = AIFindMarkerNeedsEngineer(aiBrain, eng:GetPosition(), radius, tMin, tMax, tRings, tType, validStartPos)
        end
        if not retPos then
            retPos, retName = AIFindMarkerNeedsEngineer(aiBrain, eng:GetPosition(), radius, tMin, tMax, tRings, tType, validPos)
        end
    else
        if not table.empty(validStartPos) then
            retPos, retName = AIFindMarkerNeedsEngineer(aiBrain, pos, radius, tMin, tMax, tRings, tType, validStartPos)
        end
        if not retPos then
            retPos, retName = AIFindMarkerNeedsEngineer(aiBrain, pos, radius, tMin, tMax, tRings, tType, validPos)
        end
    end

    return retPos, retName
end

---@param aiBrain AIBrain
---@param eng Unit
---@param pos Vector
---@return boolean
function EngineerTryReclaimCaptureAreaSorian(aiBrain, eng, pos)
    if not pos then
        return false
    end

    -- Check if enemy units are at location
    local checkCats = {categories.ENGINEER - categories.COMMAND, categories.STRUCTURE + (categories.MOBILE * categories.LAND - categories.ENGINEER - categories.COMMAND)}
    for k, v in checkCats do
        local checkUnits = aiBrain:GetUnitsAroundPoint(v, pos, 10, 'Enemy')
        for num, unit in checkUnits do
            if not unit.Dead and EntityCategoryContains(categories.ENGINEER, unit) then
                unit.CaptureInProgress = true
                IssueCapture({eng}, unit)
                return true
            elseif not unit.Dead and not EntityCategoryContains(categories.ENGINEER, unit) then
                unit.ReclaimInProgress = true
                IssueReclaim({eng}, unit)
                return true
            end
        end
    end

    return false
end

---@param aiBrain AIBrain
---@param locationType string
---@param assisteeType string
---@param buildingCategory string
---@param assisteeCategory string
---@return unknown
function GetAssisteesSorian(aiBrain, locationType, assisteeType, buildingCategory, assisteeCategory)
    if assisteeType == 'Factory' then
        -- Sift through the factories in the location
        local manager = aiBrain.BuilderManagers[locationType].FactoryManager
        return manager:GetFactoriesWantingAssistance(buildingCategory, assisteeCategory)
    elseif assisteeType == 'Engineer' then
        local manager = aiBrain.BuilderManagers[locationType].EngineerManager
        return manager:GetEngineersWantingAssistance(buildingCategory, assisteeCategory)
    elseif assisteeType == 'Structure' then
        local manager = aiBrain.BuilderManagers[locationType].PlatoonFormManager
        return manager:GetUnitsBeingBuilt(buildingCategory, assisteeCategory)
    elseif assisteeType == 'NonUnitBuildingStructure' then
        return GetUnitsBeingBuilt(aiBrain, locationType, assisteeCategory)
    else
        WARN('*AI ERROR: Invalid assisteeType - ' .. assisteeType)
    end

    return false
end