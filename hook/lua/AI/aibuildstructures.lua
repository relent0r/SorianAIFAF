---@param aiBrain AIBrain
---@param builder Unit
---@param whatToBuild any
---@param buildLocation Vector
---@param relative any
function AddToBuildQueueSorian(aiBrain, builder, whatToBuild, buildLocation, relative)
    if not builder.EngineerBuildQueue then
        builder.EngineerBuildQueue = {}
    end
    -- put in build queue.. but will be removed afterwards... just so that it can iteratively find new spots to build
    AIUtils.EngineerTryReclaimCaptureAreaSorian(aiBrain, builder, BuildToNormalLocation(buildLocation))
    aiBrain:BuildStructure(builder, whatToBuild, buildLocation, false)
    local newEntry = {whatToBuild, buildLocation, relative}

    table.insert(builder.EngineerBuildQueue, newEntry)
end

local AntiSpamListSorian = {}
---@param aiBrain AIBrain
---@param builder Unit
---@param buildingType string
---@param closeToBuilder boolean
---@param relative any
---@param buildingTemplate any
---@param baseTemplate any
---@param reference any
---@param NearMarkerType any
---@return boolean
function AIExecuteBuildStructureSorian(aiBrain, builder, buildingType, closeToBuilder, relative, buildingTemplate, baseTemplate, reference, NearMarkerType)
    local factionIndex = aiBrain:GetFactionIndex()
    local whatToBuild = aiBrain:DecideWhatToBuild(builder, buildingType, buildingTemplate)
    -- If the c-engine can't decide what to build, then search the build template manually.
    if not whatToBuild then
        if AntiSpamListSorian[buildingType] then
            return false
        end
        local FactionIndexToName = {[1] = 'UEF', [2] = 'AEON', [3] = 'CYBRAN', [4] = 'SERAPHIM', [5] = 'NOMADS' }
        local AIFactionName = FactionIndexToName[factionIndex]
        SPEW('*AIExecuteBuildStructureSorian: We cant decide whatToBuild! AI-faction: '..AIFactionName..', Building Type: '..repr(buildingType)..', engineer-faction: '..repr(builder.Blueprint.FactionCategory))
        -- Get the UnitId for the actual buildingType
        local BuildUnitWithID
        for Key, Data in buildingTemplate do
            if Data[1] and Data[2] and Data[1] == buildingType then
                SPEW('*AIExecuteBuildStructureSorian: Found template: '..repr(Data[1])..' - Using UnitID: '..repr(Data[2]))
                BuildUnitWithID = Data[2]
                break
            end
        end
        -- If we can't find a template, then return
        if not BuildUnitWithID then
            AntiSpamListSorian[buildingType] = true
            WARN('*AIExecuteBuildStructureSorian: No '..repr(builder.Blueprint.FactionCategory)..' unit found for template: '..repr(buildingType)..'! ')
            return false
        end
        -- get the needed tech level to build buildingType
        local BBC = __blueprints[BuildUnitWithID].CategoriesHash
        local NeedTech
        if BBC.BUILTBYCOMMANDER or BBC.BUILTBYTIER1COMMANDER or BBC.BUILTBYTIER1ENGINEER then
            NeedTech = 1
        elseif BBC.BUILTBYTIER2COMMANDER or BBC.BUILTBYTIER2ENGINEER then
            NeedTech = 2
        elseif BBC.BUILTBYTIER3COMMANDER or BBC.BUILTBYTIER3ENGINEER then
            NeedTech = 3
        end
        -- If we can't find a techlevel for the building we want to build, then return
        if not NeedTech then
            WARN('*AIExecuteBuildStructureSorian: Can\'t find techlevel for BuildUnitWithID: '..repr(BuildUnitWithID))
            return false
        else
            SPEW('*AIExecuteBuildStructureSorian: Need engineer with Techlevel ('..NeedTech..') for BuildUnitWithID: '..repr(BuildUnitWithID))
        end
        -- get the actual tech level from the builder
        local BC = builder:GetBlueprint().CategoriesHash
        if BC.TECH1 or BC.COMMAND then
            HasTech = 1
        elseif BC.TECH2 then
            HasTech = 2
        elseif BC.TECH3 then
            HasTech = 3
        end
        -- If we can't find a techlevel for the building we  want to build, return
        if not HasTech then
            WARN('*AIExecuteBuildStructureSorian: Can\'t find techlevel for engineer: '..repr(builder:GetBlueprint().BlueprintId))
            return false
        else
            SPEW('*AIExecuteBuildStructureSorian: Engineer ('..repr(builder:GetBlueprint().BlueprintId)..') has Techlevel ('..HasTech..')')
        end

        if HasTech < NeedTech then
            WARN('*AIExecuteBuildStructureSorian: TECH'..HasTech..' Unit "'..BuildUnitWithID..'" is assigned to build TECH'..NeedTech..' buildplatoon! ('..repr(buildingType)..')')
            return false
        else
            SPEW('*AIExecuteBuildStructureSorian: Engineer with Techlevel ('..HasTech..') can build TECH'..NeedTech..' BuildUnitWithID: '..repr(BuildUnitWithID))
        end

        HasFaction = builder.Blueprint.FactionCategory
        NeedFaction = string.upper(__blueprints[string.lower(BuildUnitWithID)].General.FactionName)
        if HasFaction ~= NeedFaction then
            WARN('*AIExecuteBuildStructureSorian: AI-faction: '..AIFactionName..', ('..HasFaction..') engineers can\'t build ('..NeedFaction..') structures!')
            return false
        else
            SPEW('*AIExecuteBuildStructureSorian: AI-faction: '..AIFactionName..', Engineer with faction ('..HasFaction..') can build faction ('..NeedFaction..') - BuildUnitWithID: '..repr(BuildUnitWithID))
        end

        local IsRestricted = import("/lua/game.lua").IsRestricted
        if IsRestricted(BuildUnitWithID, GetFocusArmy()) then
            WARN('*AIExecuteBuildStructureSorian: Unit is Restricted!!! Building Type: '..repr(buildingType)..', faction: '..repr(builder.Blueprint.FactionCategory)..' - Unit:'..BuildUnitWithID)
            AntiSpamListSorian[buildingType] = true
            return false
        end

        WARN('*AIExecuteBuildStructureSorian: DecideWhatToBuild call failed for Building Type: '..repr(buildingType)..', faction: '..repr(builder.Blueprint.FactionCategory)..' - Unit:'..BuildUnitWithID)
        return false
    end
    -- find a place to build it (ignore enemy locations if it's a resource)
    -- build near the base the engineer is part of, rather than the engineer location
    local relativeTo
    if closeToBuilder then
        relativeTo = builder:GetPosition()
    elseif builder.BuilderManagerData and builder.BuilderManagerData.EngineerManager then
        relativeTo = builder.BuilderManagerData.EngineerManager:GetLocationCoords()
    else
        local startPosX, startPosZ = aiBrain:GetArmyStartPos()
        relativeTo = {startPosX, 0, startPosZ}
    end
    local location = false
    if IsResource(buildingType) then
        location = aiBrain:FindPlaceToBuild(buildingType, whatToBuild, baseTemplate, relative, closeToBuilder, 'Enemy', relativeTo[1], relativeTo[3], 5)
    else
        location = aiBrain:FindPlaceToBuild(buildingType, whatToBuild, baseTemplate, relative, closeToBuilder, nil, relativeTo[1], relativeTo[3])
    end
    -- if it's a reference, look around with offsets
    if not location and reference then
        for num,offsetCheck in RandomIter({1,2,3,4,5,6,7,8}) do
            location = aiBrain:FindPlaceToBuild(buildingType, whatToBuild, BaseTmplFile['MovedTemplates'..offsetCheck][factionIndex], relative, closeToBuilder, nil, relativeTo[1], relativeTo[3])
            if location then
                break
            end
        end
    end
    -- if we have no place to build, then maybe we have a modded/new buildingType. Lets try 'T1LandFactory' as dummy and search for a place to build near base
    if not location and not IsResource(buildingType) and builder.BuilderManagerData and builder.BuilderManagerData.EngineerManager then
        --LOG('*AIExecuteBuildStructureSorian: Find no place to Build! - buildingType '..repr(buildingType)..' - ('..builder.Blueprint.FactionCategory..') Trying again with T1LandFactory and RandomIter. Searching near base...')
        relativeTo = builder.BuilderManagerData.EngineerManager:GetLocationCoords()
        for num,offsetCheck in RandomIter({1,2,3,4,5,6,7,8}) do
            location = aiBrain:FindPlaceToBuild('T1LandFactory', whatToBuild, BaseTmplFile['MovedTemplates'..offsetCheck][factionIndex], relative, closeToBuilder, nil, relativeTo[1], relativeTo[3])
            if location then
                --LOG('*AIExecuteBuildStructureSorian: Yes! Found a place near base to Build! - buildingType '..repr(buildingType))
                break
            end
        end
    end
    -- if we still have no place to build, then maybe we have really no place near the base to build. Lets search near engineer position
    if not location and not IsResource(buildingType) then
        --LOG('*AIExecuteBuildStructureSorian: Find still no place to Build! - buildingType '..repr(buildingType)..' - ('..builder.Blueprint.FactionCategory..') Trying again with T1LandFactory and RandomIter. Searching near Engineer...')
        relativeTo = builder:GetPosition()
        for num,offsetCheck in RandomIter({1,2,3,4,5,6,7,8}) do
            location = aiBrain:FindPlaceToBuild('T1LandFactory', whatToBuild, BaseTmplFile['MovedTemplates'..offsetCheck][factionIndex], relative, closeToBuilder, nil, relativeTo[1], relativeTo[3])
            if location then
                --LOG('*AIExecuteBuildStructureSorian: Yes! Found a place near engineer to Build! - buildingType '..repr(buildingType))
                break
            end
        end
    end
    -- if we have a location, build!
    if location then
        local relativeLoc = BuildToNormalLocation(location)
        if relative then
            relativeLoc = {relativeLoc[1] + relativeTo[1], relativeLoc[2] + relativeTo[2], relativeLoc[3] + relativeTo[3]}
        end
        -- put in build queue.. but will be removed afterwards... just so that it can iteratively find new spots to build
        AddToBuildQueueSorian(aiBrain, builder, whatToBuild, NormalToBuildLocation(relativeLoc), false)
        return true
    end
    -- At this point we're out of options, so move on to the next thing
    return false
end

---@param aiBrain AIBrain
---@param builder Unit
---@param buildingType string
---@param closeToBuilder any
---@param relative any
---@param buildingTemplate any
---@param baseTemplate any
---@param reference any
---@param NearMarkerType any
---@return boolean
function AIBuildBaseTemplateOrderedSorian(aiBrain, builder, buildingType , closeToBuilder, relative, buildingTemplate, baseTemplate, reference, NearMarkerType)
    local factionIndex = aiBrain:GetFactionIndex()
    local whatToBuild = aiBrain:DecideWhatToBuild(builder, buildingType, buildingTemplate)
    if whatToBuild then
        if IsResource(buildingType) then
            return AIExecuteBuildStructureSorian(aiBrain, builder, buildingType , closeToBuilder, relative, buildingTemplate, baseTemplate, reference)
        else
            for l,bType in baseTemplate do
                for m,bString in bType[1] do
                    if bString == buildingType then
                        for n,position in bType do
                            if n > 1 and aiBrain:CanBuildStructureAt(whatToBuild, BuildToNormalLocation(position)) then
                                 AddToBuildQueueSorian(aiBrain, builder, whatToBuild, position, false)
                                 return DoHackyLogic(buildingType, builder)
                            end -- if n > 1 and can build structure at
                        end -- for loop
                        break
                    end -- if bString == builderType
                end -- for loop
            end -- for loop
        end -- end else
    end -- if what to build
    return -- unsuccessful build
end

---@param aiBrain AIBrain
---@param builder Unit
---@param buildingType any
---@param closeToBuilder any
---@param relative any
---@param buildingTemplate any
---@param baseTemplate any
---@param reference any
---@param NearMarkerType any
---@return boolean
function AIBuildAdjacencySorian(aiBrain, builder, buildingType , closeToBuilder, relative, buildingTemplate, baseTemplate, reference, NearMarkerType)
    local whatToBuild = aiBrain:DecideWhatToBuild(builder, buildingType, buildingTemplate)
    if whatToBuild then
        local unitSize = aiBrain:GetUnitBlueprint(whatToBuild).Physics
        local template = {}
        table.insert(template, {})
        table.insert(template[1], { buildingType })
        for k,v in reference do
            if not v.Dead then
                local targetSize = v:GetBlueprint().Physics
                local targetPos = v:GetPosition()
                targetPos[1] = targetPos[1] - (targetSize.SkirtSizeX/2)
                targetPos[3] = targetPos[3] - (targetSize.SkirtSizeZ/2)
                -- Top/bottom of unit
                for i=0,((targetSize.SkirtSizeX/2)-1) do
                    local testPos = { targetPos[1] + 1 + (i * 2), targetPos[3]-(unitSize.SkirtSizeZ/2), 0 }
                    local testPos2 = { targetPos[1] + 1 + (i * 2), targetPos[3]+targetSize.SkirtSizeZ+(unitSize.SkirtSizeZ/2), 0 }
                    -- check if the buildplace is to close to the border or inside buildable area
                    if testPos[1] > 8 and testPos[1] < ScenarioInfo.size[1] - 8 and testPos[2] > 8 and testPos[2] < ScenarioInfo.size[2] - 8 then
                        table.insert(template[1], testPos)
                    end
                    if testPos2[1] > 8 and testPos2[1] < ScenarioInfo.size[1] - 8 and testPos2[2] > 8 and testPos2[2] < ScenarioInfo.size[2] - 8 then
                        table.insert(template[1], testPos2)
                    end
                end
                -- Sides of unit
                for i=0,((targetSize.SkirtSizeZ/2)-1) do
                    local testPos = { targetPos[1]+targetSize.SkirtSizeX + (unitSize.SkirtSizeX/2), targetPos[3] + 1 + (i * 2), 0 }
                    local testPos2 = { targetPos[1]-(unitSize.SkirtSizeX/2), targetPos[3] + 1 + (i*2), 0 }
                    if testPos[1] > 8 and testPos[1] < ScenarioInfo.size[1] - 8 and testPos[2] > 8 and testPos[2] < ScenarioInfo.size[2] - 8 then
                        table.insert(template[1], testPos)
                    end
                    if testPos2[1] > 8 and testPos2[1] < ScenarioInfo.size[1] - 8 and testPos2[2] > 8 and testPos2[2] < ScenarioInfo.size[2] - 8 then
                        table.insert(template[1], testPos2)
                    end
                end
            end
        end
        -- build near the base the engineer is part of, rather than the engineer location
        local baseLocation = {nil, nil, nil}
        if builder.BuildManagerData and builder.BuildManagerData.EngineerManager then
            baseLocation = builder.BuildManagerdata.EngineerManager.Location
        end
        local location = aiBrain:FindPlaceToBuild(buildingType, whatToBuild, template, false, builder, baseLocation[1], baseLocation[3])
        if location then
            if location[1] > 8 and location[1] < ScenarioInfo.size[1] - 8 and location[2] > 8 and location[2] < ScenarioInfo.size[2] - 8 then
                --LOG('Build '..repr(buildingType)..' at adjacency: '..repr(location) )
                AddToBuildQueueSorian(aiBrain, builder, whatToBuild, location, false)
                return true
            end
        end
        -- Build in a regular spot if adjacency not found
        return AIExecuteBuildStructureSorian(aiBrain, builder, buildingType, builder, true,  buildingTemplate, baseTemplate)
    end
    return false
end

---@param aiBrain AIBrain
---@param builder Unit
---@param buildingType string
---@param closeToBuilder any
---@param relative any
---@param buildingTemplate any
---@param baseTemplate any
---@param reference any
---@param NearMarkerType any
function WallBuilderSorian(aiBrain, builder, buildingType , closeToBuilder, relative, buildingTemplate, baseTemplate, reference, NearMarkerType)
    if not reference then
        return
    end
    local points = BuildWallsAtLocation(aiBrain, reference)
    if not points then
        return
    end
    local i = 2
    while i <= table.getn(points) do
        local point1 = FindNearestIntegers(points[i-1])
        local point2 = FindNearestIntegers(points[i])
        -------- Horizontal line
        local buildTable = {}
        if point1[2] == point2[2] then
            local xDir = -1
            if point1[1] < point2[1] then
                xDir = 1
            end
            for j = 1, math.abs(point1[1] - point2[1]) do
                table.insert(buildTable, { point1[1] + (j * xDir) + .5, point1[2] + .5, 0 })
            end
        -------- Vertical line
        elseif point1[1] == point2[1] then
            local yDir = -1
            if point1[2] < point2[2] then
                yDir = 1
            end
            for j = 1, math.abs(point1[2] - point2[2]) do
                table.insert(buildTable, { point1[1] + .5, point1[2] + (j * yDir) + .5, 0 })
            end
        -------- Angled line
        else
            local angle = (point1[1] - point2[1]) / (point1[2] - point2[2])
            if angle == 0 then
                angle = 1
            end

            local xDir = -1
            if point1[1] < point2[1] then
                xDir = 1
            end
            for j=1,math.abs(point1[1] - point2[1]) do
                table.insert(buildTable, { point1[1] + (j * xDir) - .5, (point1[2] + math.floor((angle * xDir) * (j-1)) + .5), 0 })
            end
        end
        local faction = aiBrain:GetFactionIndex()
        local whatToBuild = aiBrain:DecideWhatToBuild(builder, buildingType, buildingTemplate)
        for k,v in buildTable do
            if aiBrain:CanBuildStructureAt(whatToBuild, BuildToNormalLocation(v)) then
                --aiBrain:BuildStructure(builder, whatToBuild, v, false)
                AddToBuildQueueSorian(aiBrain, builder, whatToBuild, v, false)
            end
        end
        i = i + 1
    end
    return
end