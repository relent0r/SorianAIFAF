---@class Platoon : moho.platoon_methods
---@field PlatoonData table

SorianAIPlatoonClass = Platoon
Platoon = Class(SorianAIPlatoonClass) {
    ---@param self Platoon
    ---@return nil
    ExperimentalAIHubSorian = function(self)
        local aiBrain = self:GetBrain()
        local behaviors = import("/lua/ai/aibehaviors.lua")

        local experimental = self:GetPlatoonUnits()[1]
        if not experimental or experimental.Dead then
            return
        end
        if Random(1,5) == 3 and (not aiBrain.LastTaunt or GetGameTimeSeconds() - aiBrain.LastTaunt > 90) then
            local randelay = Random(60,180)
            aiBrain.LastTaunt = GetGameTimeSeconds() + randelay
            SUtils.AIDelayChat('enemies', ArmyBrains[aiBrain:GetArmyIndex()].Nickname, 't4taunt', nil, randelay)
        end
        local ID = experimental.UnitId

        self:SetPlatoonFormationOverride('AttackFormation')

        if ID == 'uel0401' then
            return behaviors.FatBoyBehaviorSorian(self)
        elseif ID == 'uaa0310' then
            return behaviors.CzarBehaviorSorian(self)
        elseif ID == 'xsa0402' then
            return behaviors.AhwassaBehaviorSorian(self)
        elseif ID == 'ura0401' then
            return behaviors.TickBehaviorSorian(self)
        elseif ID == 'url0401' then
            return behaviors.ScathisBehaviorSorian(self)
        elseif ID == 'uas0401' then
            return self:NavalHuntAI(self)
        elseif ID == 'ues0401' then
            return self:NavalHuntAI(self)
        end

        return behaviors.BehemothBehaviorSorian(self)
    end,

    ---@param self Platoon
    ---@return nil
    FighterDistributionHubSorian = function(self)
        local aiBrain = self:GetBrain()
        local location = self.PlatoonData.Location
        if not aiBrain.FightersHunting then
            aiBrain.FightersHunting = {}
        end
        if not aiBrain.FightersHunting[location] then
            aiBrain.FightersHunting[location] = 0
        end

        --Distribute fighters between guarding the base and hunting down targets 3:1
        if aiBrain.FightersHunting[location] < 4 then
            aiBrain.FightersHunting[location] = aiBrain.FightersHunting[location] + 1
            return self:FighterHuntAI(self)
        else
            aiBrain.FightersHunting[location] = 0
            return self:GuardBaseSorian(self)
        end
    end,

    ---@param self Platoon
    PlatoonCallForHelpAISorian = function(self)
        local aiBrain = self:GetBrain()
        local checkTime = self.PlatoonData.DistressCheckTime or 7
        local pos = self:GetPlatoonPosition()
        while aiBrain:PlatoonExists(self) and pos do
            if pos and not self.DistressCall then
                local threat = aiBrain:GetThreatAtPosition(pos, 0, true, 'AntiSurface')
                local myThreat = aiBrain:GetThreatAtPosition(pos, 0, true, 'Overall', aiBrain:GetArmyIndex())
                 --LOG('*AI DEBUG: PlatoonCallForHelpAISorian threat is: '..threat..' myThreat is: '..myThreat)
                if threat and threat > (myThreat * 1.5) then
                    --LOG('*AI DEBUG: Platoon Calling for help')
                    aiBrain:BaseMonitorPlatoonDistress(self, threat)
                    self.DistressCall = true
                end
            end
            WaitSeconds(checkTime)
            pos = self:GetPlatoonPosition()
        end
    end,

    ---@param self Platoon
    DistressResponseAISorian = function(self)
        local aiBrain = self:GetBrain()
        while aiBrain:PlatoonExists(self) do
            -- In the loop so they may be changed by other platoon things
            local distressRange = self.PlatoonData.DistressRange or aiBrain.BaseMonitor.DefaultDistressRange
            local reactionTime = self.PlatoonData.DistressReactionTime or aiBrain.BaseMonitor.PlatoonDefaultReactionTime
            local threatThreshold = self.PlatoonData.ThreatSupport or self.BaseMonitor.AlertLevel or 1
            local platoonPos = self:GetPlatoonPosition()
            local transporting = false
            units = self:GetPlatoonUnits()
            for k, v in units do
                if not v.Dead and v:IsUnitState('Attached') then
                    transporting = true
                end
                if transporting then break end
            end
            if platoonPos and not self.DistressCall and not transporting then
                -- Find a distress location within the platoons range
                local distressLocation = aiBrain:BaseMonitorDistressLocation(platoonPos, distressRange, threatThreshold)
                local moveLocation
                local threatatPos
                local myThreatatPos

                -- We found a location within our range! Activate!
                if distressLocation then
                    --LOG('*AI DEBUG: ARMY '.. aiBrain:GetArmyIndex() ..': --- DISTRESS RESPONSE AI ACTIVATION ---')

                    -- Backups old ai plan
                    local oldPlan = self:GetPlan()
                    if self.AIThread then
                        self.AIThread:Destroy()
                    end

                    -- Continue to position until the distress call wanes
                    repeat
                        moveLocation = distressLocation
                        self:Stop()
                        local cmd --= self:AggressiveMoveToLocation(distressLocation)
                        local inWater = AIAttackUtils.InWaterCheck(self)
                        if not inWater then
                            cmd = self:AggressiveMoveToLocation(distressLocation)
                        else
                            cmd = self:MoveToLocation(distressLocation, false)
                        end
                        local poscheck = self:GetPlatoonPosition()
                        local prevpos = poscheck
                        local poscounter = 0
                        local breakResponse = false
                        repeat
                            WaitSeconds(reactionTime)
                            if not aiBrain:PlatoonExists(self) then
                                return
                            end
                            poscheck = self:GetPlatoonPosition()
                            if VDist3(poscheck, prevpos) < 10 then
                                poscounter = poscounter + 1
                                if poscounter >= 3 then
                                    breakResponse = true
                                    poscounter = 0
                                end
                            elseif not SUtils.CanRespondEffectively(aiBrain, distressLocation, self) then
                                breakResponse = true
                                poscounter = 0
                            else
                                prevpos = poscheck
                                poscounter = 0
                            end
                            threatatPos = aiBrain:GetThreatAtPosition(moveLocation, 0, true, 'AntiSurface')
                            artyThreatatPos = aiBrain:GetThreatAtPosition(moveLocation, 0, true, 'Artillery')
                            myThreatatPos = aiBrain:GetThreatAtPosition(moveLocation, 0, true, 'Overall', aiBrain:GetArmyIndex())
                        until not self:IsCommandsActive(cmd) or breakResponse or ((threatatPos + artyThreatatPos) - myThreatatPos) <= threatThreshold or (inWater != AIAttackUtils.InWaterCheck(self))


                        platoonPos = self:GetPlatoonPosition()
                        if platoonPos then
                            -- Now that we have helped the first location, see if any other location needs the help
                            distressLocation = aiBrain:BaseMonitorDistressLocation(platoonPos, distressRange)
                            if distressLocation then
                                inWater = AIAttackUtils.InWaterCheck(self)
                                if not inWater then
                                    self:AggressiveMoveToLocation(distressLocation)
                                else
                                    self:MoveToLocation(distressLocation, false)
                                end
                            end
                        end
                    -- If no more calls or we are at the location; break out of the function
                    until not distressLocation or not SUtils.CanRespondEffectively(aiBrain, distressLocation, self) or (distressLocation[1] == moveLocation[1] and distressLocation[3] == moveLocation[3])

                    --LOG('*AI DEBUG: '..aiBrain.Name..' DISTRESS RESPONSE AI DEACTIVATION - oldPlan: '..oldPlan)
                    if not oldPlan then
                        units = self:GetPlatoonUnits()
                        for k, v in units do
                            if not v.Dead and EntityCategoryContains(categories.MOBILE * categories.EXPERIMENTAL, v) then
                                oldPlan = 'ExperimentalAIHubSorian'
                            elseif not v.Dead and EntityCategoryContains(categories.MOBILE * categories.LAND - categories.EXPERIMENTAL, v) then
                                oldPlan = 'AttackForceAISorian'
                            elseif not v.Dead and EntityCategoryContains(categories.AIR * categories.MOBILE * categories.ANTIAIR - categories.BOMBER - categories.TRANSPORTFOCUS - categories.EXPERIMENTAL, v) then
                                oldPlan = 'FighterHuntAI'
                            elseif not v.Dead and EntityCategoryContains(categories.AIR * categories.MOBILE * categories.BOMBER - categories.EXPERIMENTAL, v) then
                                oldPlan = 'AirHuntAI'
                            elseif not v.Dead and EntityCategoryContains(categories.MOBILE * categories.NAVAL - categories.EXPERIMENTAL, v) then
                                oldPlan = 'NavalForceAISorian'
                            end
                            if oldPlan then break end
                        end
                    end
                    self:SetAIPlan(oldPlan)
                end
            end
            WaitSeconds(11)
        end
    end,

    ---@param self Platoon
    BaseManagersDistressAISorian = function(self)
        local aiBrain = self:GetBrain()
        while aiBrain:PlatoonExists(self) do
            local distressRange = aiBrain.BaseMonitor.PoolDistressRange
            local reactionTime = aiBrain.BaseMonitor.PoolReactionTime

            local platoonUnits = self:GetPlatoonUnits()

            for locName, locData in aiBrain.BuilderManagers do
                if not locData.DistressCall then
                    local position = locData.EngineerManager:GetLocationCoords()
                    local retPos = AIUtils.RandomLocation(position[1],position[3])
                    local radius = locData.EngineerManager.Radius
                    local distressRange = locData.BaseSettings.DistressRange or aiBrain.BaseMonitor.PoolDistressRange
                    local distressLocation = aiBrain:BaseMonitorDistressLocation(position, distressRange, aiBrain.BaseMonitor.PoolDistressThreshold)

                    -- Distress !
                    if distressLocation then
                        --LOG('*AI DEBUG: ARMY '.. aiBrain:GetArmyIndex() ..': --- POOL DISTRESS RESPONSE ---')

                        -- Grab the units at the location
                        local group = self:GetPlatoonUnitsAroundPoint(categories.MOBILE - categories.EXPERIMENTAL - categories.COMMAND - categories.ENGINEER, position, radius)

                        -- Move the group to the distress location and then back to the location of the base
                        IssueClearCommands(group)
                        IssueAggressiveMove(group, distressLocation)
                        IssueMove(group, retPos)

                        -- Set distress active for duration
                        locData.DistressCall = true
                        self:ForkThread(self.UnlockBaseManagerDistressLocation, locData)
                    end
                end
            end
            WaitSeconds(aiBrain.BaseMonitor.PoolReactionTime)
        end
    end,

    ---@param self Platoon
    EnhanceAISorian = function(self)
        self:Stop()
        local aiBrain = self:GetBrain()
        local unit
        for k,v in self:GetPlatoonUnits() do
            unit = v
            break
        end
        local data = self.PlatoonData
        local numLoop = 0
        local lastEnhancement
        if unit then
            unit.Upgrading = true
            IssueStop({unit})
            IssueClearCommands({unit})
            for k,v in data.Enhancement do
                if not unit:HasEnhancement(v) then
                    local order = {
                        TaskName = "EnhanceTask",
                        Enhancement = v
                    }
                    IssueScript({unit}, order)
                    lastEnhancement = v
                    --LOG('*AI DEBUG: '..aiBrain.Nickname..' EnhanceAI Added Enhancement: '..v)
                end
            end
            WaitSeconds(data.TimeBetweenEnhancements or 1)
            repeat
                WaitSeconds(5)
                if not aiBrain:PlatoonExists(self) then
                    --LOG('*AI DEBUG: '..aiBrain.Nickname..' EnhanceAI platoon dead')
                    return
                end
                if not unit:IsUnitState('Upgrading') then
                    numLoop = numLoop + 1
                else
                    numLoop = 0
                end
                --LOG('*AI DEBUG: '..aiBrain.Nickname..' EnhanceAI loop. numLoop = '..numLoop)
            until unit.Dead or numLoop > 1 or unit:HasEnhancement(lastEnhancement)
            --LOG('*AI DEBUG: '..aiBrain.Nickname..' EnhanceAI exited loop. numLoop = '..numLoop)
            unit.Upgrading = false
        end
        --LOG('*AI DEBUG: '..aiBrain.Nickname..' EnhanceAI done')
        if data.DoNotDisband then return end
        self:PlatoonDisband()
    end,

    ---@param self Platoon
    ArtilleryAISorian = function(self)
        local aiBrain = self:GetBrain()

        local atkPri = { 'STRUCTURE STRATEGIC EXPERIMENTAL', 'EXPERIMENTAL ARTILLERY OVERLAYINDIRECTFIRE', 'STRUCTURE STRATEGIC TECH3', 'STRUCTURE NUKE TECH3', 'EXPERIMENTAL ORBITALSYSTEM', 'EXPERIMENTAL ENERGYPRODUCTION STRUCTURE', 'STRUCTURE ANTIMISSILE TECH3', 'TECH3 MASSFABRICATION', 'TECH3 ENERGYPRODUCTION', 'STRUCTURE STRATEGIC', 'STRUCTURE DEFENSE TECH3 ANTIAIR',
        'COMMAND', 'STRUCTURE DEFENSE TECH3', 'STRUCTURE DEFENSE TECH2', 'EXPERIMENTAL LAND', 'MOBILE TECH3 LAND', 'MOBILE TECH2 LAND', 'MOBILE TECH1 LAND', 'STRUCTURE FACTORY', 'ALLUNITS' }
        local atkPriTable = {}
        for k,v in atkPri do
            table.insert(atkPriTable, ParseEntityCategory(v))
        end
        self:SetPrioritizedTargetList('Artillery', atkPriTable)

        -- Set priorities on the unit so if the target has died it will reprioritize before the platoon does
        local unit = false
        for k,v in self:GetPlatoonUnits() do
            if not v.Dead then
                unit = v
                break
            end
        end
        if not unit then
            return
        end
        local bp = unit:GetBlueprint()
        local weapon = bp.Weapon[1]
        local maxRadius = weapon.MaxRadius
        local attacking = false
        unit:SetTargetPriorities(atkPriTable)

        while aiBrain:PlatoonExists(self) do
            target = AIUtils.AIFindBrainTargetInRangeSorian(aiBrain, self, 'Artillery', maxRadius, atkPri, true)
            local newtarget = false
            if aiBrain.AttackPoints and not table.empty(aiBrain.AttackPoints) then
                newtarget = AIUtils.AIFindPingTargetInRangeSorian(aiBrain, self, 'Artillery', maxRadius, atkPri, true)
                if newtarget then
                    target = newtarget
                end
            end
            if target and not unit.Dead then
                IssueClearCommands({unit})
                IssueAttack({unit}, target)
                attacking = true
            elseif not target and attacking then
                IssueClearCommands({unit})
                attacking = false
            end
            WaitSeconds(20)
        end
    end,

    ---@param self Platoon
    NukeAISAI = function(self)
        self:Stop()
        local aiBrain = self:GetBrain()
        local platoonUnits = self:GetPlatoonUnits()
        local unit
        --GET THE Launcher OUT OF THIS PLATOON
        for k, v in platoonUnits do
            if EntityCategoryContains(categories.SILO * categories.NUKE, v) then
                unit = v
                break
            end
        end

        if unit then
            local bp = unit:GetBlueprint()
            local weapon = bp.Weapon[1]
            local maxRadius = weapon.MaxRadius
            local nukePos, oldTargetLocation
            unit:SetAutoMode(true)
            while aiBrain:PlatoonExists(self) do
                while unit:GetNukeSiloAmmoCount() < 1 do
                    WaitSeconds(11)
                    if not  aiBrain:PlatoonExists(self) then
                        return
                    end
                end

                nukePos = import("/lua/ai/aibehaviors.lua").GetHighestThreatClusterLocation(aiBrain, unit)
                if nukePos then
                    IssueNuke({unit}, nukePos)
                    WaitSeconds(12)
                    IssueClearCommands({unit})
                end
                WaitSeconds(1)
            end
        end
        self:PlatoonDisband()
    end,

    ---@param self Platoon
    SatelliteAISorian = function(self)
        local aiBrain = self:GetBrain()
        local data = self.PlatoonData
        local atkPri = {}
        local atkPriTable = {}
        if data.PrioritizedCategories then
            for k,v in data.PrioritizedCategories do
                table.insert(atkPri, v)
                table.insert(atkPriTable, ParseEntityCategory(v))
            end
        end
        table.insert(atkPri, 'ALLUNITS')
        table.insert(atkPriTable, categories.ALLUNITS)
        self:SetPrioritizedTargetList('Attack', atkPriTable)

        local maxRadius = data.SearchRadius or 50
        local oldTarget = false
        local target = false

        while aiBrain:PlatoonExists(self) do
            self:MergeWithNearbyPlatoonsSorian('SatelliteAISorian', 50, true)
            target = AIUtils.AIFindUndefendedBrainTargetInRangeSorian(aiBrain, self, 'Attack', maxRadius, atkPri)
            if target and target != oldTarget and not target.Dead then
                self:Stop()
                self:AttackTarget(target)
                oldTarget = target
            end
            WaitSeconds(30)
        end
    end,

    ---@param self Platoon
    TacticalAISorian = function(self)
        self:Stop()
        local aiBrain = self:GetBrain()
        local armyIndex = aiBrain:GetArmyIndex()
        local platoonUnits = self:GetPlatoonUnits()
        local unit

        if not aiBrain:PlatoonExists(self) then return end

        --GET THE Launcher OUT OF THIS PLATOON
        for k, v in platoonUnits do
            if EntityCategoryContains(categories.STRUCTURE * categories.TACTICALMISSILEPLATFORM, v) then
                unit = v
                break
            end
        end

        if not unit then return end

        local bp = unit:GetBlueprint()
        local weapon = bp.Weapon[1]
        local maxRadius = weapon.MaxRadius
        local minRadius = weapon.MinRadius
        unit:SetAutoMode(true)
        local atkPri = { 'STRUCTURE STRATEGIC EXPERIMENTAL', 'ARTILLERY EXPERIMENTAL', 'STRUCTURE NUKE EXPERIMENTAL', 'EXPERIMENTAL ORBITALSYSTEM', 'STRUCTURE ARTILLERY TECH3',
        'STRUCTURE NUKE TECH3', 'EXPERIMENTAL ENERGYPRODUCTION STRUCTURE', 'COMMAND', 'EXPERIMENTAL MOBILE LAND', 'TECH3 MASSFABRICATION', 'TECH3 ENERGYPRODUCTION', 'TECH3 MASSPRODUCTION', 'TECH2 ENERGYPRODUCTION', 'TECH2 MASSPRODUCTION', 'STRUCTURE SHIELD' } -- 'STRUCTURE STRATEGIC', 'STRUCTURE DEFENSE TECH3', 'STRUCTURE DEFENSE TECH2', 'STRUCTURE FACTORY', 'STRUCTURE', 'LAND, NAVAL' }
        self:SetPrioritizedTargetList('Attack', { categories.STRUCTURE * categories.ARTILLERY * categories.EXPERIMENTAL, categories.STRUCTURE * categories.NUKE * categories.EXPERIMENTAL, categories.EXPERIMENTAL * categories.ORBITALSYSTEM, categories.STRUCTURE * categories.ARTILLERY * categories.TECH3,
        categories.STRUCTURE * categories.NUKE * categories.TECH3, categories.EXPERIMENTAL * categories.ENERGYPRODUCTION * categories.STRUCTURE, categories.COMMAND, categories.EXPERIMENTAL * categories.MOBILE * categories.LAND, categories.TECH3 * categories.MASSFABRICATION,
        categories.TECH3 * categories.ENERGYPRODUCTION, categories.TECH3 * categories.MASSPRODUCTION, categories.TECH2 * categories.ENERGYPRODUCTION, categories.TECH2 * categories.MASSPRODUCTION, categories.STRUCTURE * categories.SHIELD }) -- categories.STRUCTURE * categories.STRATEGIC, categories.STRUCTURE * categories.DEFENSE * categories.TECH3, categories.STRUCTURE * categories.DEFENSE * categories.TECH2, categories.STRUCTURE * categories.FACTORY, categories.STRUCTURE, categories.LAND + categories.NAVAL })
        while aiBrain:PlatoonExists(self) do
            local target = false
            local blip = false
            while unit:GetTacticalSiloAmmoCount() < 1 or not target do
                WaitSeconds(7)
                target = false
                while not target do
                    target = AIUtils.AIFindBrainTargetInRangeSorian(aiBrain, self, 'Attack', maxRadius, atkPri, true)
                    local newtarget = false
                    if aiBrain.AttackPoints and not table.empty(aiBrain.AttackPoints) then
                        newtarget = AIUtils.AIFindPingTargetInRangeSorian(aiBrain, self, 'Attack', maxRadius, atkPri, true)
                        if newtarget then
                            target = newtarget
                        end
                    end
                    if not target then
                        target = self:FindPrioritizedUnit('Attack', 'Enemy', true, unit:GetPosition(), maxRadius)
                    end
                    if target then
                        break
                    end
                    WaitSeconds(3)
                    if not aiBrain:PlatoonExists(self) then
                        return
                    end
                end
            end
            if not target.Dead then
                --LOG('*AI DEBUG: Firing Tactical Missile at enemy swine!')
                if EntityCategoryContains(categories.STRUCTURE, target) then
                    IssueTactical({unit}, target)
                else
                    targPos = SUtils.LeadTarget(self, target)
                    if targPos then
                        IssueTactical({unit}, targPos)
                    end
                end
            end
            WaitSeconds(3)
        end
    end,

    ---@param self Platoon
    ---@return nil
    ThreatStrikeSorian = function(self)
        self:Stop()
        local aiBrain = self:GetBrain()
        local threshold = self.PlatoonData.ThreatThreshold
        while aiBrain:PlatoonExists(self) do
            local bestDist = false
            local bestTarget = false
            local position = self:GetPlatoonPosition()
            if self.BaseMonitor.AlertSounded then
                for k,v in self.BaseMonitor.AlertsTable do
                    if v.Threat < threshold then
                        continue
                    end

                    local tempDist = Utilities.XZDistanceTwoVectors(position, v.Position)

                    if not bestDist or tempDist < bestDist then
                        bestDist = tempDist
                        local height = GetTerrainHeight(v.Position[1], v.Position[3])
                        local surfHeight = GetSurfaceHeight(v.Position[1], v.Position[3])
                        if surfHeight > height then
                            height = surfHeight
                        end
                        bestTarget = { v.Position[1], height, v.Position[3] }
                    end
                end
                if bestTarget then
                    local safePath, reason = AIAttackUtils.PlatoonGenerateSafePathToSorian(aiBrain, 'Air', self:GetPlatoonPosition(), bestTarget, 200)
                    if safePath then
                        local pathSize = table.getn(path)
                        for wpidx,waypointPath in path do
                            if wpidx == pathSize then
                                self:AggressiveMoveToLocation(bestTarget)
                            else
                                self:MoveToLocation(waypointPath, false)
                            end
                        end
                    else
                        self:AggressiveMoveToLocation(bestTarget)
                    end
                end
            end
            if not bestTarget then
                return self:AirHuntAI()
            end
            WaitSeconds(17)
        end
    end,

    ---@param self Platoon
    ---@return nil
    FighterHuntAI = function(self)
        self:Stop()
        local aiBrain = self:GetBrain()
        local armyIndex = aiBrain:GetArmyIndex()
        local location = self.PlatoonData.LocationType or 'MAIN'
        local radius = self.PlatoonData.Radius or 100
        local target
        local blip
        local hadtarget = false
        while aiBrain:PlatoonExists(self) do
            target = self:FindClosestUnit('Attack', 'Enemy', true, categories.AIR - categories.POD)
            local newtarget = false
            if aiBrain.T4ThreatFound['Air'] then
                newtarget = self:FindClosestUnit('Attack', 'Enemy', true, categories.EXPERIMENTAL * categories.AIR)
                if newtarget then
                    target = newtarget
                end
            end
            if target and newtarget and target:GetFractionComplete() == 1
            and SUtils.GetThreatAtPosition(aiBrain, target:GetPosition(), 1, 'AntiAir', {'Air'}) < (AIAttackUtils.GetAirThreatOfUnits(self) * .6) then
                blip = target:GetBlip(armyIndex)
                self:Stop()
                self:AttackTarget(target)
                hadtarget = true
            elseif target and target:GetFractionComplete() == 1
            and SUtils.GetThreatAtPosition(aiBrain, target:GetPosition(), 1, 'AntiAir', {'Air'}) < (AIAttackUtils.GetAirThreatOfUnits(self) * .6) then
                blip = target:GetBlip(armyIndex)
                self:Stop()
                self:AggressiveMoveToLocation(table.copy(target:GetPosition()))
                hadtarget = true
            elseif not target and hadtarget then
                for k,v in AIUtils.GetBasePatrolPoints(aiBrain, location, radius, 'Air') do
                   self:Patrol(v)
                end
                hadtarget = false
                return self:GuardExperimentalSorian(self.FighterHuntAI)
            end
            local waitLoop = 0
            repeat
                WaitSeconds(1)
                waitLoop = waitLoop + 1
            until waitLoop >= 17 or (target and (target.Dead or not target:GetPosition()))
        end
    end,

    ---## Function: GuardMarkerSorian
    --- Will guard the location of a marker
    ---@param self Platoon
    GuardMarkerSorian = function(self)
        local aiBrain = self:GetBrain()

        local platLoc = self:GetPlatoonPosition()

        if not aiBrain:PlatoonExists(self) or not platLoc then
            return
        end

        -----------------------------------------------------------------------
        -- Platoon Data
        -----------------------------------------------------------------------
        -- type of marker to guard
        -- Start location = 'Start Location'... see MarkerTemplates.lua for other types
        local markerType = self.PlatoonData.MarkerType or 'Expansion Area'

        -- what should we look for for the first marker?  This can be 'Random',
        -- 'Threat' or 'Closest'
        local moveFirst = self.PlatoonData.MoveFirst or 'Threat'

        -- should our next move be no move be (same options as before) as well as 'None'
        -- which will cause the platoon to guard the first location they get to
        local moveNext = self.PlatoonData.MoveNext or 'None'

        -- Minimum distance when looking for closest
        local avoidClosestRadius = self.PlatoonData.AvoidClosestRadius or 0

        -- set time to wait when guarding a location with moveNext = 'None'
        local guardTimer = self.PlatoonData.GuardTimer or 0

        -- threat type to look at
        local threatType = self.PlatoonData.ThreatType or 'AntiSurface'

        -- should we look at our own threat or the enemy's
        local bSelfThreat = self.PlatoonData.SelfThreat or false

        -- if true, look to guard highest threat, otherwise,
        -- guard the lowest threat specified
        local bFindHighestThreat = self.PlatoonData.FindHighestThreat or false

        -- minimum threat to look for
        local minThreatThreshold = self.PlatoonData.MinThreatThreshold or -1
        -- maximum threat to look for
        local maxThreatThreshold = self.PlatoonData.MaxThreatThreshold  or 99999999

        -- Avoid bases (true or false)
        local bAvoidBases = self.PlatoonData.AvoidBases or false

        -- Radius around which to avoid the main base
        local avoidBasesRadius = self.PlatoonData.AvoidBasesRadius or 0

        -- Use Aggresive Moves Only
        local bAggroMove = self.PlatoonData.AggressiveMove or false

        local PlatoonFormation = self.PlatoonData.UseFormation or 'NoFormation'
        -----------------------------------------------------------------------


        AIAttackUtils.GetMostRestrictiveLayer(self)
        self:SetPlatoonFormationOverride(PlatoonFormation)
        local markerLocations = AIUtils.AIGetMarkerLocations(aiBrain, markerType)

        local bestMarker = false

        if not self.LastMarker then
            self.LastMarker = {nil,nil}
        end

        -- look for a random marker
        if moveFirst == 'Random' then
            if table.getn(markerLocations) <= 2 then
                self.LastMarker[1] = nil
                self.LastMarker[2] = nil
            end
            for _,marker in RandomIter(markerLocations) do
                if table.getn(markerLocations) <= 2 then
                    self.LastMarker[1] = nil
                    self.LastMarker[2] = nil
                end
                if self:AvoidsBasesSorian(marker.Position, bAvoidBases, avoidBasesRadius) then
                    if self.LastMarker[1] and marker.Position[1] == self.LastMarker[1][1] and marker.Position[3] == self.LastMarker[1][3] then
                        continue
                    end
                    if self.LastMarker[2] and marker.Position[1] == self.LastMarker[2][1] and marker.Position[3] == self.LastMarker[2][3] then
                        continue
                    end
                    bestMarker = marker
                    break
                end
            end
        elseif moveFirst == 'Threat' then
            --Guard the closest least-defended marker
            local bestMarkerThreat = 0
            if not bFindHighestThreat then
                bestMarkerThreat = 99999999
            end

            local bestDistSq = 99999999


            -- find best threat at the closest distance
            for _,marker in markerLocations do
                local markerThreat
                if bSelfThreat then
                    markerThreat = aiBrain:GetThreatAtPosition(marker.Position, 0, true, threatType, aiBrain:GetArmyIndex())
                else
                    markerThreat = aiBrain:GetThreatAtPosition(marker.Position, 0, true, threatType)
                end
                local distSq = VDist2Sq(marker.Position[1], marker.Position[3], platLoc[1], platLoc[3])

                if markerThreat >= minThreatThreshold and markerThreat <= maxThreatThreshold then
                    if self:AvoidsBasesSorian(marker.Position, bAvoidBases, avoidBasesRadius) then
                        if self.IsBetterThreat(bFindHighestThreat, markerThreat, bestMarkerThreat) then
                            bestDistSq = distSq
                            bestMarker = marker
                            bestMarkerThreat = markerThreat
                        elseif markerThreat == bestMarkerThreat then
                            if distSq < bestDistSq then
                                bestDistSq = distSq
                                bestMarker = marker
                                bestMarkerThreat = markerThreat
                            end
                        end
                     end
                 end
            end

        else
            -- if we didn't want random or threat, assume closest (but avoid ping-ponging)
            local bestDistSq = 99999999
            if table.getn(markerLocations) <= 2 then
                self.LastMarker[1] = nil
                self.LastMarker[2] = nil
            end
            for _,marker in markerLocations do
                local distSq = VDist2Sq(marker.Position[1], marker.Position[3], platLoc[1], platLoc[3])
                if self:AvoidsBasesSorian(marker.Position, bAvoidBases, avoidBasesRadius) and distSq > (avoidClosestRadius * avoidClosestRadius) then
                    if distSq < bestDistSq then
                        if self.LastMarker[1] and marker.Position[1] == self.LastMarker[1][1] and marker.Position[3] == self.LastMarker[1][3] then
                            continue
                        end
                        if self.LastMarker[2] and marker.Position[1] == self.LastMarker[2][1] and marker.Position[3] == self.LastMarker[2][3] then
                            continue
                        end
                        bestDistSq = distSq
                        bestMarker = marker
                    end
                end
            end
        end


        -- did we find a threat?
        local usedTransports = false
        if bestMarker then
            self.LastMarker[2] = self.LastMarker[1]
            self.LastMarker[1] = bestMarker.Position
            --LOG("GuardMarker: Attacking " .. bestMarker.Name)
            local path, reason = AIAttackUtils.PlatoonGenerateSafePathToSorian(aiBrain, self.MovementLayer, self:GetPlatoonPosition(), bestMarker.Position, 200)
            --local success, bestGoalPos = AIAttackUtils.CheckPlatoonPathingEx(self, bestMarker.Position)
            IssueClearCommands(self:GetPlatoonUnits())
            if path then
                local position = self:GetPlatoonPosition()
                if VDist2(position[1], position[3], bestMarker.Position[1], bestMarker.Position[3]) > 512 then
                    usedTransports = AIAttackUtils.SendPlatoonWithTransportsSorian(aiBrain, self, bestMarker.Position, true, false, false)
                elseif VDist2(position[1], position[3], bestMarker.Position[1], bestMarker.Position[3]) > 256 then
                    usedTransports = AIAttackUtils.SendPlatoonWithTransportsSorian(aiBrain, self, bestMarker.Position, false, false, false)
                end
                if not usedTransports then
                    local pathLength = table.getn(path)
                    for i=1, pathLength-1 do
                        if bAggroMove then
                            self:AggressiveMoveToLocation(path[i])
                        else
                            self:MoveToLocation(path[i], false)
                        end
                    end
                end
            elseif (not path and reason == 'NoPath') then
                usedTransports = AIAttackUtils.SendPlatoonWithTransportsSorian(aiBrain, self, bestMarker.Position, true, false, true)
            else
                self:PlatoonDisband()
                return
            end

            if not path and not usedTransports then
                self:PlatoonDisband()
                return
            end

            if moveNext == 'None' then
                -- guard
                IssueGuard(self:GetPlatoonUnits(), bestMarker.Position)
                -- guard forever
                if guardTimer <= 0 then return end
            else
                -- otherwise, we're moving to the location
                self:AggressiveMoveToLocation(bestMarker.Position)
            end

            -- wait till we get there
            local oldPlatPos = self:GetPlatoonPosition()
            local StuckCount = 0
            repeat
                WaitSeconds(5)
                platLoc = self:GetPlatoonPosition()
                if VDist3(oldPlatPos, platLoc) < 1 then
                    StuckCount = StuckCount + 1
                else
                    StuckCount = 0
                end
                if StuckCount > 5 then
                    return self:GuardMarkerSorian()
                end
                oldPlatPos = platLoc
            until VDist2Sq(platLoc[1], platLoc[3], bestMarker.Position[1], bestMarker.Position[3]) < 64 or not aiBrain:PlatoonExists(self)

            -- if we're supposed to guard for some time
            if moveNext == 'None' then
                -- this won't be 0... see above
                WaitSeconds(guardTimer)
                self:PlatoonDisband()
                return
            end

            if moveNext == 'Guard Base' then
                return self:GuardBaseSorian()
            end

            -- we're there... wait here until we're done
            local numGround = aiBrain:GetNumUnitsAroundPoint((categories.LAND + categories.NAVAL + categories.STRUCTURE), bestMarker.Position, 15, 'Enemy')
            while numGround > 0 and aiBrain:PlatoonExists(self) do
                WaitSeconds(Random(5,10))
                numGround = aiBrain:GetNumUnitsAroundPoint((categories.LAND + categories.NAVAL + categories.STRUCTURE), bestMarker.Position, 15, 'Enemy')
            end

            if not aiBrain:PlatoonExists(self) then
                return
            end

            -- set our MoveFirst to our MoveNext
            self.PlatoonData.MoveFirst = moveNext
            return self:GuardMarkerSorian()
        else
            -- no marker found, disband!
            self:PlatoonDisband()
        end
    end,

    ---comment
    ---@param self any
    GuardBaseSorian = function(self)
        self:Stop()
        local aiBrain = self:GetBrain()
        local armyIndex = aiBrain:GetArmyIndex()
        local target = false
        local basePosition = false
        local radius = self.PlatoonData.Radius or 100
        local patrolling = false

        if self.PlatoonData.LocationType and self.PlatoonData.LocationType != 'NOTMAIN' then
            basePosition = aiBrain.BuilderManagers[self.PlatoonData.LocationType].Position
        else
            local platoonPosition = self:GetPlatoonPosition()
            if platoonPosition then
                basePosition = aiBrain:FindClosestBuilderManagerPosition(self:GetPlatoonPosition())
        end
        end

        if not basePosition then
            return
        end

        local guardRadius = self.PlatoonData.GuardRadius or 200
        local mapSizeX, mapSizeZ = GetMapSize()
        local T4Radius = math.sqrt((mapSizeX * mapSizeX) + (mapSizeZ * mapSizeZ)) / 2

        while aiBrain:PlatoonExists(self) do
            target = self:FindClosestUnit('Attack', 'Enemy', true, categories.ALLUNITS - categories.WALL)
            local newtarget = false
            if aiBrain.T4ThreatFound['Air'] then
                newtarget = self:FindClosestUnit('Attack', 'Enemy', true, categories.EXPERIMENTAL * categories.AIR)
                if newtarget then
                    target = newtarget
                end
            end
            if target and newtarget and not target.Dead and target:GetFractionComplete() == 1
            and SUtils.XZDistanceTwoVectorsSq(target:GetPosition(), basePosition) < T4Radius * T4Radius then
                blip = target:GetBlip(armyIndex)
                self:Stop()
                self:AttackTarget(target)
                patrolling = false
            elseif target and not target.Dead and SUtils.XZDistanceTwoVectorsSq(target:GetPosition(), basePosition) < guardRadius * guardRadius then
                self:Stop()
                self:AggressiveMoveToLocation(target:GetPosition())
                patrolling = false
            elseif not patrolling then
                local position = AIUtils.RandomLocation(basePosition[1],basePosition[3])
                self:MoveToLocation(position, false)
                for k,v in AIUtils.GetBasePatrolPoints(aiBrain, basePosition, radius, 'Air') do
                    self:Patrol(v)
                end
                patrolling = true
            end
            WaitSeconds(5)
        end
    end,

    ---comment
    ---@param self any
    NavalForceAISorian = function(self)
        self:Stop()
        local aiBrain = self:GetBrain()

        AIAttackUtils.GetMostRestrictiveLayer(self)

        local platoonUnits = self:GetPlatoonUnits()
        local numberOfUnitsInPlatoon = table.getn(platoonUnits)
        local oldNumberOfUnitsInPlatoon = numberOfUnitsInPlatoon
        local stuckCount = 0

        self.PlatoonAttackForce = true
        -- formations have penalty for taking time to form up... not worth it here
        -- maybe worth it if we micro
        --self:SetPlatoonFormationOverride('GrowthFormation')
        local PlatoonFormation = self.PlatoonData.UseFormation or 'No Formation'
        self:SetPlatoonFormationOverride(PlatoonFormation)

        for k,v in self:GetPlatoonUnits() do
            if v.Dead then
                continue
            end

            if v.Layer == 'Sub' then
                continue
            end

            if v:TestCommandCaps('RULEUCC_Dive') then
                IssueDive({v})
            end
        end

        local maxRange, selectedWeaponArc, turretPitch = AIAttackUtils.GetNavalPlatoonMaxRangeSorian(aiBrain, self)
--      local quickReset = false

        while aiBrain:PlatoonExists(self) do
            local pos = self:GetPlatoonPosition() -- update positions; prev position done at end of loop so not done first time

            -- if we can't get a position, then we must be dead
            if not pos then
                break
            end

            -- pick out the enemy
            if aiBrain:GetCurrentEnemy() and aiBrain:GetCurrentEnemy():IsDefeated() then
                aiBrain:PickEnemyLogicSorian()
            end

            -- merge with nearby platoons
            --if aiBrain:GetThreatAtPosition(pos, 1, true, 'AntiSurface') < 1 then
                self:MergeWithNearbyPlatoonsSorian('NavalForceAISorian', 20)
            --end

            -- rebuild formation
            platoonUnits = self:GetPlatoonUnits()
            numberOfUnitsInPlatoon = table.getn(platoonUnits)
            -- if we have a different number of units in our platoon, regather
            if (oldNumberOfUnitsInPlatoon != numberOfUnitsInPlatoon) and aiBrain:GetThreatAtPosition(pos, 1, true, 'AntiSurface') < 1 then
                self:StopAttack()
                self:SetPlatoonFormationOverride(PlatoonFormation)
                oldNumberOfUnitsInPlatoon = numberOfUnitsInPlatoon
            end

            local cmdQ = {}
            -- fill cmdQ with current command queue for each unit
            for k,v in platoonUnits do
                if not v.Dead then
                    local unitCmdQ = v:GetCommandQueue()
                    for cmdIdx,cmdVal in unitCmdQ do
                        table.insert(cmdQ, cmdVal)
                        break
                    end
                end
            end

            if (oldNumberOfUnitsInPlatoon != numberOfUnitsInPlatoon) then
                maxRange, selectedWeaponArc, turretPitch = AIAttackUtils.GetNavalPlatoonMaxRangeSorian(aiBrain, self)
            end

            if not maxRange then maxRange = 180 end

            -- if we're on our final push through to the destination, and we find a unit close to our destination
            --local closestTarget = self:FindClosestUnit('attack', 'enemy', true, categories.ALLUNITS)
            local closestTarget = SUtils.FindClosestUnitPosToAttack(aiBrain, self, 'attack', maxRange + 20, categories.ALLUNITS - categories.AIR - categories.WALL, selectedWeaponArc, turretPitch)
            local nearDest = false
            local oldPathSize = table.getn(self.LastAttackDestination)

            if self.LastAttackDestination then
                nearDest = oldPathSize == 0 or VDist3(self.LastAttackDestination[oldPathSize], pos) < maxRange + 20
            end

            -- if we're near our destination and we have a unit closeby to kill, kill it
            if table.getn(cmdQ) <= 1 and closestTarget and nearDest then
                self:StopAttack()
                if PlatoonFormation != 'No Formation' then
                    self:AggressiveMoveToLocation(closestTarget:GetPosition())
                    --IssueFormAttack(platoonUnits, closestTarget, PlatoonFormation, 0)
                    --self:AttackTarget(closestTarget)
                    --IssueAttack(platoonUnits, closestTarget)
                else
                    self:AggressiveMoveToLocation(closestTarget:GetPosition())
                    --IssueFormAttack(platoonUnits, closestTarget, PlatoonFormation, 0)
                    --self:AttackTarget(closestTarget)
                    --IssueAttack(platoonUnits, closestTarget)
                end
                cmdQ = {1}
--              quickReset = true
            -- if we have a target and can attack it, attack!
            elseif closestTarget then
                self:StopAttack()
                if PlatoonFormation != 'No Formation' then
                    self:AggressiveMoveToLocation(closestTarget:GetPosition())
                    --IssueFormAttack(platoonUnits, closestTarget, PlatoonFormation, 0)
                    --self:AttackTarget(closestTarget)
                    --IssueAttack(platoonUnits, closestTarget)
                else
                    self:AggressiveMoveToLocation(closestTarget:GetPosition())
                    --IssueFormAttack(platoonUnits, closestTarget, PlatoonFormation, 0)
                    --self:AttackTarget(closestTarget)
                    --IssueAttack(platoonUnits, closestTarget)
                end
                cmdQ = {1}
--              quickReset = true
            -- if we have nothing to do, but still have a path (because of one of the above)
            elseif table.empty(cmdQ) and oldPathSize > 0 then
                self.LastAttackDestination = nil
                self:StopAttack()
                cmdQ = AIAttackUtils.AIPlatoonNavalAttackVectorSorian(aiBrain, self)
                stuckCount = 0
            -- if we have nothing to do, try finding something to do
            elseif table.empty(cmdQ) then
                self:StopAttack()
                cmdQ = AIAttackUtils.AIPlatoonNavalAttackVectorSorian(aiBrain, self)
                stuckCount = 0
            -- if we've been stuck and unable to reach next marker? Ignore nearby stuff and pick another target
            elseif self.LastPosition and VDist2Sq(self.LastPosition[1], self.LastPosition[3], pos[1], pos[3]) < (self.PlatoonData.StuckDistance or 50) then
                stuckCount = stuckCount + 1
                if stuckCount >= 2 then
                    self:StopAttack()
                    self.LastAttackDestination = nil
                    cmdQ = AIAttackUtils.AIPlatoonNavalAttackVectorSorian(aiBrain, self)
                    stuckCount = 0
                end
            else
                stuckCount = 0
            end

            self.LastPosition = pos

            --wait a while if we're stuck so that we have a better chance to move
--          if quickReset then
--              quickReset = false
--              WaitSeconds(6)
--          else
                WaitSeconds(Random(5,11) + 2 * stuckCount)
--          end
        end
    end,

    ---comment
    ---@param self any
    ---@return boolean
    GatherUnitsSorian = function(self)
        if table.getn(self:GetPlatoonUnits()) == 1 then return true end
        local pos = self:GetPlatoonPosition()
        local unitsSet = true
        for k,v in self:GetPlatoonUnits() do
            if not v.Dead and SUtils.XZDistanceTwoVectorsSq(v:GetPosition(), pos) > 3600 then --60
               unitsSet = false
               break
            end
        end
        local aiBrain = self:GetBrain()
        if not unitsSet then
            local gatherPoint = AIUtils.AIGetClosestMarkerLocation(aiBrain, 'Rally Point', pos[1], pos[3])
            if not gatherPoint or SUtils.XZDistanceTwoVectorsSq(pos, gatherPoint) > 6400 then --80
                gatherPoint = AIUtils.AIGetClosestMarkerLocation(aiBrain, 'Defensive Point', pos[1], pos[3])
                if not gatherPoint or SUtils.XZDistanceTwoVectorsSq(pos, gatherPoint) > 6400 then --80
                    gatherPoint = self:GetPlatoonPosition()
                end
            end
            local cmd = self:MoveToLocation(gatherPoint, false)
            local counter = 0
            repeat
                WaitSeconds(1)
                counter = counter + 1
                if not aiBrain:PlatoonExists(self) then
                    return false
                end
                unitsSet = true
                for k,v in self:GetPlatoonUnits() do
                    if not v.Dead and SUtils.XZDistanceTwoVectorsSq(v:GetPosition(), gatherPoint) > 3600 then --60
                        unitsSet = false
                        break
                    end
                end
            until unitsSet or not self:IsCommandsActive(cmd) or counter >= 20
        end

        return true
    end,

    ---@param self Platoon
    ---@param nextAIFunc function
    ---@return any
    GuardExperimentalSorian = function(self, nextAIFunc)
        local aiBrain = self:GetBrain()

        if not aiBrain:PlatoonExists(self) or not self:GetPlatoonPosition() then
            return
        end

        AIAttackUtils.GetMostRestrictiveLayer(self)

        local unitToGuard = false
        local units = aiBrain:GetListOfUnits(categories.MOBILE * categories.EXPERIMENTAL - categories.url0401, false)
        for k,v in units do
            if v:GetFractionComplete() == 1 and ((self.MovementLayer == 'Air' and SUtils.GetGuardCount(aiBrain, v, categories.AIR) < 20) or ((self.MovementLayer == 'Land' or self.MovementLayer == 'Amphibious') and EntityCategoryContains(categories.LAND, v) and SUtils.GetGuardCount(aiBrain, v, categories.LAND) < 20)) then --not v.BeingGuarded then
                unitToGuard = v
                --v.BeingGuarded = true
            end
        end

        local guardTime = 0
        if unitToGuard and not unitToGuard.Dead then
            IssueGuard(self:GetPlatoonUnits(), unitToGuard)

            while aiBrain:PlatoonExists(self) and not unitToGuard.Dead do
                guardTime = guardTime + 5
                WaitSeconds(5)

                if aiBrain.T4ThreatFound['Air'] and self.MovementLayer == 'Air' then
                    local target = self:FindClosestUnit('Attack', 'Enemy', true, categories.EXPERIMENTAL * categories.AIR)
                    if target and target:GetFractionComplete() == 1 then
                        return self:FighterHuntAI()
                    end
                end

                if self.PlatoonData.T4GuardTimeLimit and guardTime >= self.PlatoonData.T4GuardTimeLimit
                or (not unitToGuard.Dead and unitToGuard.Layer == 'Seabed' and self.MovementLayer == 'Land') then
                    break
                end
            end
        end

        ----Tail call into the next ai function
        WaitSeconds(1)
        if type(nextAIFunc) == 'function' then
            return nextAIFunc(self)
        end

        if not unitToGuard then
            return self:ReturnToBaseAISorian()
        end

        return self:GuardExperimentalSorian(nextAIFunc)
    end,

    ---@param self Platoon
    SorianManagerEngineerAssistAI = function(self)
        local aiBrain = self:GetBrain()
        local assistData = self.PlatoonData.Assist
        local beingBuilt = false
        self:SorianEconAssistBody()
        WaitSeconds(assistData.Time or 60)
        local eng = self:GetPlatoonUnits()[1]
        if eng:GetGuardedUnit() then
            beingBuilt = eng:GetGuardedUnit()
        end
        if beingBuilt and assistData.AssistUntilFinished then
            while beingBuilt:IsUnitState('Building') or beingBuilt:IsUnitState('Upgrading') do
                WaitSeconds(5)
            end
        end
        if not aiBrain:PlatoonExists(self) then --or assistData.PermanentAssist then
            --LOG('*AI DEBUG: Engie perma assisting')
            SUtils.AISendPing(eng:GetPosition(), 'move', aiBrain:GetArmyIndex())
            return
        end
        self:PlatoonDisband()
    end,

    ---@param self Platoon
    SorianEconAssistBody = function(self)
        local eng = self:GetPlatoonUnits()[1]
        if not eng then
            self:PlatoonDisband()
            return
        end
        local aiBrain = self:GetBrain()
        local assistData = self.PlatoonData.Assist
        local assistee = false

        eng.AssistPlatoon = self

        if not assistData.AssistLocation or not assistData.AssisteeType then
            WARN('*AI WARNING: Disbanding Assist platoon that does not have either AssistLocation or AssisteeType')
            self:PlatoonDisband()
        end

        local beingBuilt = assistData.BeingBuiltCategories or { 'ALLUNITS' }

        local assisteeCat = assistData.AssisteeCategory or categories.ALLUNITS
        if type(assisteeCat) == 'string' then
            assisteeCat = ParseEntityCategory(assisteeCat)
        end

        -- loop through different categories we are looking for
        for _,catString in beingBuilt do
            -- Track all valid units in the assist list so we can load balance for factories

            local category = ParseEntityCategory(catString)

            local assistList = AIUtils.GetAssisteesSorian(aiBrain, assistData.AssistLocation, assistData.AssisteeType, category, assisteeCat)

            if not table.empty(assistList) then
                -- only have one unit in the list; assist it
                if table.getn(assistList) == 1
                and (not assistData.AssistRange or SUtils.XZDistanceTwoVectorsSq(eng:GetPosition(), assistList[1]:GetPosition()) < assistData.AssistRange) then
                    assistee = assistList[1]
                    break
                else
                    -- Find the unit with the least number of assisters; assist it
                    local lowNum = false
                    local lowUnit = false
                    for k,v in assistList do
                        if (not lowNum or table.getn(v:GetGuards()) < lowNum) and
                        (not assistData.AssistRange or SUtils.XZDistanceTwoVectorsSq(eng:GetPosition(), v:GetPosition()) < assistData.AssistRange) then
                            lowNum = v:GetGuards()
                            lowUnit = v
                        end
                    end
                    assistee = lowUnit
                    break
                end
            end
        end
        -- assist unit
        if assistee then
            self:Stop()
            eng.AssistSet = true
            IssueGuard({eng}, assistee)
        else
            self:PlatoonDisband()
        end
    end,

    ---@param self Platoon
    LandScoutingAISorian = function(self)
        AIAttackUtils.GetMostRestrictiveLayer(self)

        local aiBrain = self:GetBrain()
        local scout = self:GetPlatoonUnits()[1]

        -- build scoutlocations if not already done.
        if not aiBrain.InterestList then
            aiBrain:BuildScoutLocationsSorian()
        end

        --If we have cloaking (are cybran), then turn on our cloaking
        if self.PlatoonData.UseCloak and scout:TestToggleCaps('RULEUTC_CloakToggle') then
            scout:SetScriptBit('RULEUTC_CloakToggle', false)
        end

        while not scout.Dead do
            --Head towards the the area that has not had a scout sent to it in a while
            local targetData = false

            --For every scouts we send to all opponents, send one to scout a low pri area.
            if aiBrain.IntelData.HiPriScouts < aiBrain.NumOpponents and not table.empty(aiBrain.InterestList.HighPriority) then
                targetData = aiBrain.InterestList.HighPriority[1]
                aiBrain.IntelData.HiPriScouts = aiBrain.IntelData.HiPriScouts + 1
                targetData.LastScouted = GetGameTimeSeconds()

                aiBrain:SortScoutingAreas(aiBrain.InterestList.HighPriority)

            elseif not table.empty(aiBrain.InterestList.LowPriority) then
                targetData = aiBrain.InterestList.LowPriority[1]
                aiBrain.IntelData.HiPriScouts = 0
                targetData.LastScouted = GetGameTimeSeconds()

                aiBrain:SortScoutingAreas(aiBrain.InterestList.LowPriority)
            else
                --Reset number of scoutings and start over
                aiBrain.IntelData.HiPriScouts = 0
            end

            --Is there someplace we should scout?
            if targetData then
                --Can we get there safely?
                local path, reason = AIAttackUtils.PlatoonGenerateSafePathToSorian(aiBrain, self.MovementLayer, scout:GetPosition(), targetData.Position, 100)

                IssueClearCommands(self:GetPlatoonUnits())

                if path then
                    local pathLength = table.getn(path)
                    for i=1, pathLength-1 do
                        self:MoveToLocation(path[i], false)
                    end
                end

                self:MoveToLocation(targetData.Position, false)

                --Scout until we reach our destination
                while not scout.Dead and not scout:IsIdleState() do
                    WaitSeconds(2.5)
                end
            end

            WaitSeconds(1)
        end
    end,

    ---@param self Platoon
    AirScoutingAISorian = function(self)

        local aiBrain = self:GetBrain()
        local scout = self:GetPlatoonUnits()[1]
        local badScouting = false

        -- build scoutlocations if not already done.
        if not aiBrain.InterestList then
            aiBrain:BuildScoutLocationsSorian()
        end

        if scout:TestToggleCaps('RULEUTC_CloakToggle') then
            scout:SetScriptBit('RULEUTC_CloakToggle', false)
        end

        while not scout.Dead do
            local targetArea = false
            local highPri = false

            local mustScoutArea, mustScoutIndex = aiBrain:GetUntaggedMustScoutArea()
            local unknownThreats = aiBrain:GetThreatsAroundPosition(scout:GetPosition(), 16, true, 'Unknown')

            --1) If we have any "must scout" (manually added) locations that have not been scouted yet, then scout them
            if mustScoutArea then
                mustScoutArea.TaggedBy = scout
                targetArea = mustScoutArea.Position

            --2) Scout "unknown threat" areas with a threat higher than 25
            elseif not table.empty(unknownThreats) and unknownThreats[1][3] > 25 then
                aiBrain:AddScoutArea({unknownThreats[1][1], 0, unknownThreats[1][2]})

            --3) Scout high priority locations
            elseif aiBrain.IntelData.AirHiPriScouts < aiBrain.NumOpponents and aiBrain.IntelData.AirLowPriScouts < 1
            and not table.empty(aiBrain.InterestList.HighPriority) then
                aiBrain.IntelData.AirHiPriScouts = aiBrain.IntelData.AirHiPriScouts + 1

                highPri = true

                targetData = aiBrain.InterestList.HighPriority[1]
                targetData.LastScouted = GetGameTimeSeconds()
                targetArea = targetData.Position

                aiBrain:SortScoutingAreas(aiBrain.InterestList.HighPriority)

            --4) Every time we scout NumOpponents number of high priority locations, scout a low priority location
            elseif aiBrain.IntelData.AirLowPriScouts < 1 and not table.empty(aiBrain.InterestList.LowPriority) then
                aiBrain.IntelData.AirHiPriScouts = 0
                aiBrain.IntelData.AirLowPriScouts = aiBrain.IntelData.AirLowPriScouts + 1

                targetData = aiBrain.InterestList.LowPriority[1]
                targetData.LastScouted = GetGameTimeSeconds()
                targetArea = targetData.Position

                aiBrain:SortScoutingAreas(aiBrain.InterestList.LowPriority)
            else
                --Reset number of scoutings and start over
                aiBrain.IntelData.AirLowPriScouts = 0
                aiBrain.IntelData.AirHiPriScouts = 0
            end

            --Air scout do scoutings.
            if targetArea then
                badScouting = false
                self:Stop()

                local vec = self:DoAirScoutVecs(scout, targetArea)

                while not scout.Dead and not scout:IsIdleState() do

                    --If we're close enough...
                    if VDist2Sq(vec[1], vec[3], scout:GetPosition()[1], scout:GetPosition()[3]) < 15625 then
                        if mustScoutArea then
                            --Untag and remove
                            for idx,loc in aiBrain.InterestList.MustScout do
                                if loc == mustScoutArea then
                                   table.remove(aiBrain.InterestList.MustScout, idx)
                                   break
                                end
                            end
                        end
                        --Break within 125 ogrids of destination so we don't decelerate trying to stop on the waypoint.
                        break
                    end

                    if VDist3(scout:GetPosition(), targetArea) < 25 then
                        break
                    end

                    WaitSeconds(5)
                end
            elseif not badScouting then
                self:Stop()
                badScouting = true
                markers = AIUtils.AIGetMarkerLocations(aiBrain, 'Combat Zone')
                if markers and not table.empty(markers) then
                    local ScoutPath = {}
                    local MarkerCount = table.getn(markers)
                    for i = 1, MarkerCount do
                        rand = Random(1, MarkerCount + 1 - i)
                        table.insert(ScoutPath, markers[rand])
                        table.remove(markers, rand)
                    end
                    for k, v in ScoutPath do
                        self:Patrol(v.Position)
                    end
                end
                WaitSeconds(1)
            end
            WaitTicks(1)
        end
    end,

    ---@param self Platoon
    ---@return nil
    ScoutingAISorian = function(self)
        AIAttackUtils.GetMostRestrictiveLayer(self)

        if self.MovementLayer == 'Air' then
            return self:AirScoutingAISorian()
        else
            return self:LandScoutingAISorian()
        end
    end,

    ---@param self Platoon
    HuntAISorian = function(self)
        self:Stop()
        local aiBrain = self:GetBrain()
        local armyIndex = aiBrain:GetArmyIndex()
        local target
        local blip
        local platoonUnits = self:GetPlatoonUnits()
        local PlatoonFormation = self.PlatoonData.UseFormation or 'NoFormation'
        self:SetPlatoonFormationOverride(PlatoonFormation)
        while aiBrain:PlatoonExists(self) do
            local mySurfaceThreat = AIAttackUtils.GetSurfaceThreatOfUnits(self)
            local inWater = AIAttackUtils.InWaterCheck(self)
            local pos = self:GetPlatoonPosition()
            local threatatLocation = aiBrain:GetThreatAtPosition(pos, 1, true, 'AntiSurface')
            target = self:FindClosestUnit('Attack', 'Enemy', true, categories.ALLUNITS - categories.AIR - categories.NAVAL - categories.SCOUT)
            if target then
                blip = target:GetBlip(armyIndex)
                self:Stop()
                if not inWater then
                    IssueAggressiveMove(platoonUnits, target:GetPosition())
                else
                    IssueMove(platoonUnits, target:GetPosition())
                end
            end
            WaitSeconds(17)
        end
    end,

    ---@param self Platoon
    CDRHuntAISorian = function(self)
        self:Stop()
        local aiBrain = self:GetBrain()
        local armyIndex = aiBrain:GetArmyIndex()
        local target
        local platoonUnits = self:GetPlatoonUnits()
        local eng
        for k, v in platoonUnits do
            if not v.Dead and EntityCategoryContains(categories.COMMAND, v) then
                eng = v
            end
        end
        local leashRange = eng.Mult * 100
        local weapBPs = eng:GetBlueprint().Weapon
        local weapon
        eng.Fighting = true
        for k,v in weapBPs do
            if v.Label == 'OverCharge' then
                weapon = v
                break
            end
        end
        local weapRange = weapon.MaxRadius
        local movingToScout = false
        local initialMove = true
        while aiBrain:PlatoonExists(self) do
            local mySurfaceThreat = eng:GetBlueprint().Defense.SurfaceThreatLevel or 75
            local pos = self:GetPlatoonPosition()
            local target = self:FindClosestUnit('support', 'Enemy', true, categories.ALLUNITS - categories.AIR - categories.NAVAL - categories.SCOUT)
            if target and not target.Dead and SUtils.XZDistanceTwoVectorsSq(target:GetPosition(), eng.CDRHome) < (leashRange * leashRange) and
            aiBrain:GetThreatBetweenPositions(pos, target:GetPosition(), nil, 'AntiSurface') < mySurfaceThreat then
                movingToScout = false
                local targetLoc = target:GetPosition()
                self:Stop()
                if aiBrain:GetEconomyStored('ENERGY') >= weapon.EnergyRequired and VDist2Sq(targetLoc[1], targetLoc[3], pos[1], pos[3]) <= weapRange * weapRange then
                    IssueClearCommands({eng})
                    IssueOverCharge({eng}, target)
                else
                    IssueClearCommands({eng})
                    IssueMove({eng}, targetLoc)
                end
            elseif not movingToScout then
                self:Stop()
                local DefSpots = AIUtils.AIGetSortedDefensiveLocationsFromLast(aiBrain, 10)
                if not table.empty(DefSpots) then
                    for k,v in DefSpots do
                        if SUtils.XZDistanceTwoVectorsSq(v, eng.CDRHome) < (leashRange * leashRange) and (SUtils.XZDistanceTwoVectorsSq(v, eng.CDRHome) > SUtils.XZDistanceTwoVectorsSq(pos, eng.CDRHome) and initialMove) then
                            movingToScout = true
                            self:MoveToLocation(v, false)
                        end
                    end
                    if not movingToScout then
                        initialMove = false
                    end
                 end
            end
            WaitSeconds(5)
        end
        eng.Fighting = false
        eng.PlatoonHandle:PlatoonDisband()
    end,

    ---@param self Platoon
    ---@return any
    GhettoAISorian = function(self)
        self:Stop()
        local aiBrain = self:GetBrain()
        local target
        local haveTransports = false
        local counter = 0
        local units = self:GetPlatoonUnits()
        while true do
            haveTransports = AIUtils.GetTransports(platoon)
            counter = counter + 1
            if haveTransports or counter > 11 then break end
            WaitSeconds(10)
        end

        if not haveTransports then
            return self:HuntAISorian()
        end

        local transport
        for k,v in self:GetPlatoonUnits() do
            if EntityCategoryContains(categories.TRANSPORTFOCUS, v) then
                transport = v
                break
            end
        end

        AIUtils.UseTransportsGhetto(units, {transport})

        local data = self.PlatoonData
        local maxRadius = data.SearchRadius or 50
        local categoryList = {}
        local atkPri = {}
        if data.PrioritizedCategories then
            for k,v in data.PrioritizedCategories do
                table.insert(atkPri, v)
                table.insert(categoryList, ParseEntityCategory(v))
            end
        end
        table.insert(atkPri, 'ALLUNITS')
        table.insert(categoryList, categories.ALLUNITS)
        self:SetPrioritizedTargetList('Attack', categoryList)

        while aiBrain:PlatoonExists(self) do
            local pos = self:GetPlatoonPosition()
            target = AIUtils.AIFindBrainTargetInRange(aiBrain, self, 'Attack', maxRadius * 25, atkPri, aiBrain:GetCurrentEnemy())
            if target then
                self:AttackTarget(target)
            end
            if transport:GetHealthPercent() < .35 then
                IssueTransportUnload(transport, self:GetPlatoonPosition())
            end
            WaitSeconds(17)
        end
    end,

    ---@param self Platoon
    AttackForceAISorian = function(self)
        self:Stop()
        local aiBrain = self:GetBrain()

        -- get units together
        if not self:GatherUnitsSorian() then
            self:PlatoonDisband()
        end

        -- Setup the formation based on platoon functionality

        local enemy = aiBrain:GetCurrentEnemy()

        local platoonUnits = self:GetPlatoonUnits()
        local numberOfUnitsInPlatoon = table.getn(platoonUnits)
        local oldNumberOfUnitsInPlatoon = numberOfUnitsInPlatoon
        local platoonTechLevel = SUtils.GetPlatoonTechLevel(platoonUnits)
        local platoonThreatTable = {4,28,80}
        local stuckCount = 0

        self.PlatoonAttackForce = true
        -- formations have penalty for taking time to form up... not worth it here
        -- maybe worth it if we micro
        --self:SetPlatoonFormationOverride('GrowthFormation')
        local bAggro = self.PlatoonData.AggressiveMove or false
        local PlatoonFormation = self.PlatoonData.UseFormation or 'No Formation'
        self:SetPlatoonFormationOverride(PlatoonFormation)
        local maxRange, selectedWeaponArc, turretPitch = AIAttackUtils.GetLandPlatoonMaxRangeSorian(aiBrain, self)
        --local quickReset = false

        while aiBrain:PlatoonExists(self) do
            local pos = self:GetPlatoonPosition() -- update positions; prev position done at end of loop so not done first time

            -- if we can't get a position, then we must be dead
            if not pos then
                self:PlatoonDisband()
            end


            -- if we're using a transport, wait for a while
            if self.UsingTransport then
                WaitSeconds(10)
                continue
            end

            -- pick out the enemy
            if aiBrain:GetCurrentEnemy() and aiBrain:GetCurrentEnemy():IsDefeated() then
                aiBrain:PickEnemyLogicSorian()
            end

            -- merge with nearby platoons
            if aiBrain:PlatoonExists(self) then
                self:MergeWithNearbyPlatoonsSorian('AttackForceAISorian', 10)
            end

            -- rebuild formation
            platoonUnits = self:GetPlatoonUnits()
            numberOfUnitsInPlatoon = table.getn(platoonUnits)
            -- if we have a different number of units in our platoon, regather
            local threatatLocation = aiBrain:GetThreatAtPosition(pos, 1, true, 'AntiSurface')
            if (oldNumberOfUnitsInPlatoon != numberOfUnitsInPlatoon) and threatatLocation < 1 then
                self:StopAttack()
                self:SetPlatoonFormationOverride(PlatoonFormation)
                oldNumberOfUnitsInPlatoon = numberOfUnitsInPlatoon
            end

            -- deal with lost-puppy transports
            local strayTransports = {}
            for k,v in platoonUnits do
                if EntityCategoryContains(categories.TRANSPORTATION, v) then
                    table.insert(strayTransports, v)
                end
            end
            if not table.empty(strayTransports) then
                local dropPoint = pos
                dropPoint[1] = dropPoint[1] + Random(-3, 3)
                dropPoint[3] = dropPoint[3] + Random(-3, 3)
                IssueTransportUnload(strayTransports, dropPoint)
                WaitSeconds(10)
                local strayTransports = {}
                for k,v in platoonUnits do
                    local parent = v:GetParent()
                    if parent and EntityCategoryContains(categories.TRANSPORTATION, parent) then
                        table.insert(strayTransports, parent)
                        break
                    end
                end
                if not table.empty(strayTransports) then
                    local MAIN = aiBrain.BuilderManagers.MAIN
                    if MAIN then
                        dropPoint = MAIN.Position
                        IssueTransportUnload(strayTransports, dropPoint)
                        WaitSeconds(30)
                    end
                end
                self.UsingTransport = false
                AIUtils.ReturnTransportsToPool(strayTransports, true)
                platoonUnits = self:GetPlatoonUnits()
            end


            --Disband platoon if it's all air units, so they can be picked up by another platoon
            local mySurfaceThreat = AIAttackUtils.GetSurfaceThreatOfUnits(self)
            if mySurfaceThreat == 0 and AIAttackUtils.GetAirThreatOfUnits(self) > 0 then
                self:PlatoonDisband()
                return
            end

            local cmdQ = {}
            -- fill cmdQ with current command queue for each unit
            for k,v in platoonUnits do
                if not v.Dead then
                    local unitCmdQ = v:GetCommandQueue()
                    for cmdIdx,cmdVal in unitCmdQ do
                        table.insert(cmdQ, cmdVal)
                        break
                    end
                end
            end

            if (oldNumberOfUnitsInPlatoon != numberOfUnitsInPlatoon) then
                maxRange, selectedWeaponArc, turretPitch = AIAttackUtils.GetLandPlatoonMaxRangeSorian(aiBrain, self)
            end

            if not maxRange then maxRange = 50 end

            -- if we're on our final push through to the destination, and we find a unit close to our destination
            --local closestTarget = self:FindClosestUnit('attack', 'enemy', true, categories.ALLUNITS)
            local closestTarget = SUtils.FindClosestUnitPosToAttack(aiBrain, self, 'attack', maxRange + 20, categories.ALLUNITS - categories.AIR - categories.NAVAL - categories.SCOUT, selectedWeaponArc, turretPitch)
            local nearDest = false
            local oldPathSize = table.getn(self.LastAttackDestination)
            if self.LastAttackDestination then
                nearDest = oldPathSize == 0 or VDist3(self.LastAttackDestination[oldPathSize], pos) < 20
            end

            local inWater = AIAttackUtils.InWaterCheck(self)

        -- if we're near our destination and we have a unit closeby to kill, kill it
            if table.getn(cmdQ) <= 1 and closestTarget and nearDest then
                self:StopAttack()
                if not inWater then
                    self:AggressiveMoveToLocation(closestTarget:GetPosition())
                else
                    self:MoveToLocation(closestTarget:GetPosition(), false)
                end
                cmdQ = {1}
--              quickReset = true
            -- if we have a target and can attack it, attack!
            elseif closestTarget then
                self:StopAttack()
                if not inWater then
                    self:AggressiveMoveToLocation(closestTarget:GetPosition())
                else
                    self:MoveToLocation(closestTarget:GetPosition(), false)
                end
                cmdQ = {1}
--              quickReset = true
            -- if we have nothing to do, but still have a path (because of one of the above)
            elseif table.empty(cmdQ) and oldPathSize > 0 then
                self.LastAttackDestination = {}
                self:StopAttack()
                cmdQ = AIAttackUtils.AIPlatoonSquadAttackVectorSorian(aiBrain, self, bAggro)
                stuckCount = 0
            -- if we have nothing to do, try finding something to do
            elseif table.empty(cmdQ) then
                self:StopAttack()
                cmdQ = AIAttackUtils.AIPlatoonSquadAttackVectorSorian(aiBrain, self, bAggro)
                stuckCount = 0
            -- if we've been stuck and unable to reach next marker? Ignore nearby stuff and pick another target
            elseif self.LastPosition and VDist2Sq(self.LastPosition[1], self.LastPosition[3], pos[1], pos[3]) < (self.PlatoonData.StuckDistance or 8) then
                stuckCount = stuckCount + 1
                if stuckCount >= 2 then
                    self:StopAttack()
                    self.LastAttackDestination = {}
                    cmdQ = AIAttackUtils.AIPlatoonSquadAttackVectorSorian(aiBrain, self, bAggro)
                    stuckCount = 0
                end
            else
                stuckCount = 0
            end

            self.LastPosition = pos

--[[            if table.empty(cmdQ) then --and mySurfaceThreat < 4 then
                -- if we have a low threat value, then go and defend an engineer or a base
                if mySurfaceThreat < platoonThreatTable[platoonTechLevel]
                    and mySurfaceThreat > 0 and not self.PlatoonData.NeverGuard
                    and not (self.PlatoonData.NeverGuardEngineers and self.PlatoonData.NeverGuardBases) then
                    --LOG('*DEBUG: Trying to guard')
                    --if platoonTechLevel > 1 then
                    --  return self:GuardExperimentalSorian(self.AttackForceAISorian)
                    --else
                        return self:GuardEngineer(self.AttackForceAISorian)
                    --end
                end

                -- we have nothing to do, so find the nearest base and disband
                if not self.PlatoonData.NeverMerge then
                    return self:ReturnToBaseAISorian()
                end
                WaitSeconds(5)
            else
                -- wait a little longer if we're stuck so that we have a better chance to move
                if quickReset then
                    quickReset = false
                    WaitSeconds(6)
                else ]]--
                WaitSeconds(Random(5,11) + 2 * stuckCount)
--              end
--            end
        end
    end,

    ---@param self Platoon
    ---@return nil
    ReturnToBaseAISorian = function(self)
        local aiBrain = self:GetBrain()

        if not aiBrain:PlatoonExists(self) or not self:GetPlatoonPosition() then
            return
        end

        local bestBase = false
        local bestBaseName = ""
        local bestDistSq = 999999999
        local platPos = self:GetPlatoonPosition()

        for baseName, base in aiBrain.BuilderManagers do
            local distSq = VDist2Sq(platPos[1], platPos[3], base.Position[1], base.Position[3])

            if distSq < bestDistSq then
                bestBase = base
                bestBaseName = baseName
                bestDistSq = distSq
            end
        end

        if bestBase then
            AIAttackUtils.GetMostRestrictiveLayer(self)
            local path, reason = AIAttackUtils.PlatoonGenerateSafePathToSorian(aiBrain, self.MovementLayer, self:GetPlatoonPosition(), bestBase.Position, 200)
            IssueClearCommands(self:GetPlatoonUnits())

            if path then
                local pathLength = table.getn(path)
                for i=1, pathLength-1 do
                    self:MoveToLocation(path[i], false)
                end
            end
            self:MoveToLocation(bestBase.Position, false)

            local oldDistSq = 0
            while aiBrain:PlatoonExists(self) do
                platPos = self:GetPlatoonPosition()
                local distSq = VDist2Sq(platPos[1], platPos[3], bestBase.Position[1], bestBase.Position[3])
                if distSq < 5625 then -- 75 * 75
                    self:PlatoonDisband()
                    return
                end
                WaitSeconds(10)
                -- if we haven't moved in 10 seconds... go back to attacking
                if (distSq - oldDistSq) < 25 then -- 5 * 5
                    break
                end
                oldDistSq = distSq
            end
        end
        -- default to returning to attacking
        return self:AttackForceAISorian()
    end,

    ---@param self Platoon
    StrikeForceAISorian = function(self)
        local aiBrain = self:GetBrain()
        local armyIndex = aiBrain:GetArmyIndex()
        local data = self.PlatoonData
        local categoryList = {}
        local atkPri = {}
        if data.PrioritizedCategories then
            for k,v in data.PrioritizedCategories do
                table.insert(atkPri, v)
                table.insert(categoryList, ParseEntityCategory(v))
            end
        end
        table.insert(atkPri, 'ALLUNITS')
        table.insert(categoryList, categories.ALLUNITS)
        self:SetPrioritizedTargetList('Attack', categoryList)
        local target = false
        local oldTarget = false
        local blip = false
        local maxRadius = data.SearchRadius or 50
        local movingToScout = false
        AIAttackUtils.GetMostRestrictiveLayer(self)
        while aiBrain:PlatoonExists(self) do
            if target then
                local targetCheck = true
                for k,v in atkPri do
                    local category = ParseEntityCategory(v)
                    if EntityCategoryContains(category, target) and v != 'ALLUNITS' then
                        targetCheck = false
                        break
                    end
                end
                if targetCheck then
                    target = false
                    oldTarget = false
                end
            end
            if not target or target.Dead or not target:GetPosition() then
                if aiBrain:GetCurrentEnemy() and aiBrain:GetCurrentEnemy():IsDefeated() then
                    aiBrain:PickEnemyLogicSorian()
                end
                --local mult = { 1,10,25 }
                --for _,i in mult do
                    target = AIUtils.AIFindBrainTargetInRange(aiBrain, self, 'Attack', maxRadius * 25, atkPri, aiBrain:GetCurrentEnemy())
                --    if target then
                --        break
                --    end
                --    WaitSeconds(3)
                --    if not aiBrain:PlatoonExists(self) then
                --        return
                --    end
                --end
                local newtarget = false
                if AIAttackUtils.GetSurfaceThreatOfUnits(self) > 0 and (aiBrain.T4ThreatFound['Land'] or aiBrain.T4ThreatFound['Naval'] or aiBrain.T4ThreatFound['Structure']) then
                    newtarget = self:FindClosestUnit('Attack', 'Enemy', true, categories.EXPERIMENTAL * (categories.LAND + categories.NAVAL + categories.STRUCTURE + categories.ARTILLERY))
                elseif AIAttackUtils.GetAirThreatOfUnits(self) > 0 and aiBrain.T4ThreatFound['Air'] then
                    newtarget = self:FindClosestUnit('Attack', 'Enemy', true, categories.EXPERIMENTAL * categories.AIR)
                end
                if newtarget then
                    target = newtarget
                end
                if target and (target != oldTarget or movingToScout) then
                    oldTarget = target
                    local path, reason = AIAttackUtils.PlatoonGenerateSafePathToSorian(aiBrain, self.MovementLayer, self:GetPlatoonPosition(), target:GetPosition(), 10)
                    self:Stop()
                    if not path then
                        if reason == 'NoStartNode' or reason == 'NoEndNode' then
                            if not data.UseMoveOrder then
                                self:AttackTarget(target)
                            else
                                self:MoveToLocation(table.copy(target:GetPosition()), false)
                            end
                        end
                    else
                        local pathSize = table.getn(path)
                        for wpidx,waypointPath in path do
                            if wpidx == pathSize and not data.UseMoveOrder then
                                self:AttackTarget(target)
                            else
                                self:MoveToLocation(waypointPath, false)
                            end
                        end
                    end
                    movingToScout = false
                elseif not movingToScout and not target and self.MovementLayer != 'Water' then
                    movingToScout = true
                    self:Stop()
                    local MassSpots = AIUtils.AIGetSortedMassLocations(aiBrain, 10, nil, nil, nil, nil, self:GetPlatoonPosition())
                    if not table.empty(MassSpots) then
                        for k,v in MassSpots do
                            self:MoveToLocation(v, false)
                        end
                    else
                        local x,z = aiBrain:GetArmyStartPos()
                        local position = AIUtils.RandomLocation(x,z)
                        local safePath, reason = AIAttackUtils.PlatoonGenerateSafePathToSorian(aiBrain, 'Air', self:GetPlatoonPosition(), position, 200)
                        if safePath then
                            for _,p in safePath do
                                self:MoveToLocation(p, false)
                            end
                        else
                            self:MoveToLocation(position, false)
                        end
                    end
                elseif not movingToScout and not target and self.MovementLayer == 'Water' then
                    movingToScout = true
                    self:Stop()
                    local scoutPath = {}
                    scoutPath = AIUtils.AIGetSortedNavalLocations(self:GetBrain())
                    for k, v in scoutPath do
                        self:Patrol(v)
                    end
                end
            end
            if self.MovementLayer == 'Air' then
                local waitLoop = 0
                repeat
                    WaitSeconds(1)
                    waitLoop = waitLoop + 1
                until waitLoop >= 7 or (target and (target.Dead or not target:GetPosition()))
            else
                WaitSeconds(7)
            end
        end
    end,

    ---@param self Platoon
    ---@return nil
    EngineerBuildAISorian = function(self)
        self:Stop()
        local aiBrain = self:GetBrain()
        local cons = self.PlatoonData.Construction
        local platoonUnits = self:GetPlatoonUnits()
        local armyIndex = aiBrain:GetArmyIndex()
        local x,z = aiBrain:GetArmyStartPos()
        local buildingTmpl, buildingTmplFile, baseTmpl, baseTmplFile

        local eng
        for k, v in platoonUnits do
            if not v.Dead and EntityCategoryContains(categories.CONSTRUCTION, v) then
                if not eng then
                    eng = v
                else
                    IssueClearCommands({v})
                    IssueGuard({v}, eng)
                end
            end
        end

        if not eng or eng.Dead then
            coroutine.yield(1)
            self:PlatoonDisband()
            return
        end

        local FactionToIndex  = { UEF = 1, AEON = 2, CYBRAN = 3, SERAPHIM = 4, NOMADS = 5}
        local factionIndex = cons.FactionIndex or FactionToIndex[eng.Blueprint.FactionCategory]

        if not SUtils.CheckForMapMarkers(aiBrain) and cons.NearMarkerType and (cons.NearMarkerType == 'Rally Point' or
        cons.NearMarkerType == 'Protected Experimental Construction') then
            cons.NearMarkerType = nil
            cons.BaseTemplate = nil
        end

        buildingTmplFile = import(cons.BuildingTemplateFile or '/lua/BuildingTemplates.lua')
        baseTmplFile = import(cons.BaseTemplateFile or '/lua/BaseTemplates.lua')
        buildingTmpl = buildingTmplFile[(cons.BuildingTemplate or 'BuildingTemplates')][factionIndex]
        baseTmpl = baseTmplFile[(cons.BaseTemplate or 'BaseTemplates')][factionIndex]

        if self.PlatoonData.NeedGuard then
            eng.NeedGuard = true
        end

        -------- CHOOSE APPROPRIATE BUILD FUNCTION AND SETUP BUILD VARIABLES --------
        local reference = false
        local refName = false
        local buildFunction
        local closeToBuilder
        local relative
        local baseTmplList = {}

        -- if we have nothing to build, disband!
        if not cons.BuildStructures then
            coroutine.yield(1)
            self:PlatoonDisband()
            return
        end

        if cons.NearUnitCategory then
            self:SetPrioritizedTargetList('support', {ParseEntityCategory(cons.NearUnitCategory)})
            local unitNearBy = self:FindPrioritizedUnit('support', 'Ally', false, self:GetPlatoonPosition(), cons.NearUnitRadius or 50)
            --LOG("ENGINEER BUILD: " .. cons.BuildStructures[1] .." attempt near: ", cons.NearUnitCategory)
            if unitNearBy then
                reference = table.copy(unitNearBy:GetPosition())
                -- get commander home position
                --LOG("ENGINEER BUILD: " .. cons.BuildStructures[1] .." Near unit: ", cons.NearUnitCategory)
                if cons.NearUnitCategory == 'COMMAND' and unitNearBy.CDRHome then
                    reference = unitNearBy.CDRHome
                end
            else
                reference = table.copy(eng:GetPosition())
            end
            relative = false
            buildFunction = AIBuildStructures.AIExecuteBuildStructureSorian
            table.insert(baseTmplList, AIBuildStructures.AIBuildBaseTemplateFromLocation(baseTmpl, reference))
        elseif cons.Wall then
            local pos = aiBrain:PBMGetLocationCoords(cons.LocationType) or cons.Position or self:GetPlatoonPosition()
            local radius = cons.LocationRadius or aiBrain:PBMGetLocationRadius(cons.LocationType) or 100
            relative = false
            reference = AIUtils.GetLocationNeedingWalls(aiBrain, 200, 5, 'DEFENSE', cons.ThreatMin, cons.ThreatMax, cons.ThreatRings)
            table.insert(baseTmplList, 'Blank')
            buildFunction = AIBuildStructures.WallBuilderSorian
        elseif cons.NearBasePatrolPoints then
            relative = false
            reference = AIUtils.GetBasePatrolPointsSorian(aiBrain, cons.Location or 'MAIN', cons.Radius or 100)
            baseTmpl = baseTmplFile['ExpansionBaseTemplates'][factionIndex]
            for k,v in reference do
                table.insert(baseTmplList, AIBuildStructures.AIBuildBaseTemplateFromLocation(baseTmpl, v))
            end
            -- Must use BuildBaseOrdered to start at the marker; otherwise it builds closest to the eng
            buildFunction = AIBuildStructures.AIBuildBaseTemplateOrderedSorian
        elseif cons.NearMarkerType and cons.ExpansionBase then
            local pos = aiBrain:PBMGetLocationCoords(cons.LocationType) or cons.Position or self:GetPlatoonPosition()
            local radius = cons.LocationRadius or aiBrain:PBMGetLocationRadius(cons.LocationType) or 100

            if cons.FireBase and cons.FireBaseRange then
                reference, refName = AIUtils.AIFindFirebaseLocationSorian(aiBrain, cons.LocationType, cons.FireBaseRange, cons.NearMarkerType,
                                                    cons.ThreatMin, cons.ThreatMax, cons.ThreatRings, cons.ThreatType,
                                                    cons.MarkerUnitCount, cons.MarkerUnitCategory, cons.MarkerRadius)
                if not reference or not refName then
                    self:PlatoonDisband()
                end
            elseif cons.NearMarkerType == 'Expansion Area' then
                reference, refName = AIUtils.AIFindExpansionAreaNeedsEngineer(aiBrain, cons.LocationType,
                        (cons.LocationRadius or 100), cons.ThreatMin, cons.ThreatMax, cons.ThreatRings, cons.ThreatType)
                -- didn't find a location to build at
                if not reference or not refName then
                    self:PlatoonDisband()
                end
            elseif cons.NearMarkerType == 'Naval Area' then
                reference, refName = AIUtils.AIFindNavalAreaNeedsEngineer(aiBrain, cons.LocationType,
                        (cons.LocationRadius or 100), cons.ThreatMin, cons.ThreatMax, cons.ThreatRings, cons.ThreatType)
                -- didn't find a location to build at
                if not reference or not refName then
                    self:PlatoonDisband()
                end
            else
                local mapSizeX, mapSizeZ = GetMapSize()
                if mapSizeX > 512 and mapSizeZ > 512 then
                    reference, refName = AIUtils.AIFindStartLocationNeedsEngineerSorian(aiBrain, cons.LocationType,
                            (cons.LocationRadius or 100), cons.ThreatMin, cons.ThreatMax, cons.ThreatRings, cons.ThreatType)
                else
                    reference, refName = AIUtils.AIFindStartLocationNeedsEngineer(aiBrain, cons.LocationType,
                            (cons.LocationRadius or 100), cons.ThreatMin, cons.ThreatMax, cons.ThreatRings, cons.ThreatType)
                end
                -- didn't find a location to build at
                if not reference or not refName then
                    self:PlatoonDisband()
                end
            end

            -- If moving far from base, tell the assisting platoons to not go with
            if cons.FireBase or cons.ExpansionBase then
                local guards = eng:GetGuards()
                for k,v in guards do
                    if not v.Dead and v.PlatoonHandle and EntityCategoryContains(categories.CONSTRUCTION, v) then
                        v.PlatoonHandle:PlatoonDisband()
                    end
                end
            end

            if not cons.BaseTemplate and (cons.NearMarkerType == 'Naval Area' or cons.NearMarkerType == 'Defensive Point' or cons.NearMarkerType == 'Expansion Area') then
                baseTmpl = baseTmplFile['ExpansionBaseTemplates'][factionIndex]
            end
            if cons.ExpansionBase and refName then
                AIBuildStructures.AINewExpansionBase(aiBrain, refName, reference, eng, cons)
            end
            relative = false
            if reference and aiBrain:GetThreatAtPosition(reference , 1, true, 'AntiSurface') > 0 then
                --aiBrain:ExpansionHelp(eng, reference)
            end
            table.insert(baseTmplList, AIBuildStructures.AIBuildBaseTemplateFromLocation(baseTmpl, reference))
            buildFunction = AIBuildStructures.AIBuildBaseTemplate
        elseif cons.NearMarkerType and cons.FireBase and cons.FireBaseRange then
            baseTmpl = baseTmplFile['ExpansionBaseTemplates'][factionIndex]

            relative = false
            local pos = self:GetPlatoonPosition()
            reference, refName = AIUtils.AIFindFirebaseLocationSorian(aiBrain, cons.LocationType, cons.FireBaseRange, cons.NearMarkerType,
                                                cons.ThreatMin, cons.ThreatMax, cons.ThreatRings, cons.ThreatType,
                                                cons.MarkerUnitCount, cons.MarkerUnitCategory, cons.MarkerRadius)

            table.insert(baseTmplList, AIBuildStructures.AIBuildBaseTemplateFromLocation(baseTmpl, reference))

            buildFunction = AIBuildStructures.AIExecuteBuildStructureSorian
        elseif cons.NearMarkerType and cons.NearMarkerType == 'Defensive Point' then
            baseTmpl = baseTmplFile['ExpansionBaseTemplates'][factionIndex]

            relative = false
            local pos = self:GetPlatoonPosition()
            reference, refName = AIUtils.AIFindDefensivePointNeedsStructureSorian(aiBrain, cons.LocationType, (cons.LocationRadius or 100),
                            cons.MarkerUnitCategory, cons.MarkerRadius, cons.MarkerUnitCount, (cons.ThreatMin or 0), (cons.ThreatMax or 1),
                            (cons.ThreatRings or 1), (cons.ThreatType or 'AntiSurface'))

            table.insert(baseTmplList, AIBuildStructures.AIBuildBaseTemplateFromLocation(baseTmpl, reference))

            buildFunction = AIBuildStructures.AIExecuteBuildStructureSorian
        elseif cons.NearMarkerType and cons.NearMarkerType == 'Naval Defensive Point' then
            baseTmpl = baseTmplFile['ExpansionBaseTemplates'][factionIndex]

            relative = false
            local pos = self:GetPlatoonPosition()
            reference, refName = AIUtils.AIFindNavalDefensivePointNeedsStructure(aiBrain, cons.LocationType, (cons.LocationRadius or 100),
                            cons.MarkerUnitCategory, cons.MarkerRadius, cons.MarkerUnitCount, (cons.ThreatMin or 0), (cons.ThreatMax or 1),
                            (cons.ThreatRings or 1), (cons.ThreatType or 'AntiSurface'))

            table.insert(baseTmplList, AIBuildStructures.AIBuildBaseTemplateFromLocation(baseTmpl, reference))

            buildFunction = AIBuildStructures.AIExecuteBuildStructureSorian
        elseif cons.NearMarkerType and cons.NearMarkerType == 'Expansion Area' then
            baseTmpl = baseTmplFile['ExpansionBaseTemplates'][factionIndex]

            relative = false
            local pos = self:GetPlatoonPosition()
            reference, refName = AIUtils.AIFindExpansionPointNeedsStructure(aiBrain, cons.LocationType, (cons.LocationRadius or 100),
                            cons.MarkerUnitCategory, cons.MarkerRadius, cons.MarkerUnitCount, (cons.ThreatMin or 0), (cons.ThreatMax or 1),
                            (cons.ThreatRings or 1), (cons.ThreatType or 'AntiSurface'))

            table.insert(baseTmplList, AIBuildStructures.AIBuildBaseTemplateFromLocation(baseTmpl, reference))

            buildFunction = AIBuildStructures.AIExecuteBuildStructureSorian
        elseif cons.NearMarkerType then
            --WARN('*Data weird for builder named - ' .. self.BuilderName)
            if not cons.ThreatMin or not cons.ThreatMax or not cons.ThreatRings then
                cons.ThreatMin = -1000000
                cons.ThreatMax = 1000000
                cons.ThreatRings = 0
            end
            if not cons.BaseTemplate and (cons.NearMarkerType == 'Defensive Point' or cons.NearMarkerType == 'Expansion Area') then
                baseTmpl = baseTmplFile['ExpansionBaseTemplates'][factionIndex]
            end
            relative = false
            local pos = self:GetPlatoonPosition()
            reference, refName = AIUtils.AIGetClosestThreatMarkerLoc(aiBrain, cons.NearMarkerType, pos[1], pos[3],
                                                            cons.ThreatMin, cons.ThreatMax, cons.ThreatRings)
            if cons.ExpansionBase and refName then
                AIBuildStructures.AINewExpansionBase(aiBrain, refName, reference, (cons.ExpansionRadius or 100), cons.ExpansionTypes, nil, cons)
            end
            if reference and aiBrain:GetThreatAtPosition(reference, 1, true) > 0 then
                --aiBrain:ExpansionHelp(eng, reference)
            end
            table.insert(baseTmplList, AIBuildStructures.AIBuildBaseTemplateFromLocation(baseTmpl, reference))
            buildFunction = AIBuildStructures.AIExecuteBuildStructureSorian
        elseif cons.AvoidCategory then
            relative = false
            local pos = aiBrain.BuilderManagers[eng.BuilderManagerData.LocationType].EngineerManager.Location
            local cat = ParseEntityCategory(cons.AdjacencyCategory)
            local avoidCat = ParseEntityCategory(cons.AvoidCategory)
            local radius = (cons.AdjacencyDistance or 50)
            if not pos or not pos then
                coroutine.yield(1)
                self:PlatoonDisband()
                return
            end
            reference  = AIUtils.FindUnclutteredArea(aiBrain, cat, pos, radius, cons.maxUnits, cons.maxRadius, avoidCat)
            buildFunction = AIBuildStructures.AIBuildAdjacencySorian
            table.insert(baseTmplList, baseTmpl)
        elseif cons.AdjacencyCategory then
            relative = false
            local pos = aiBrain.BuilderManagers[eng.BuilderManagerData.LocationType].EngineerManager.Location
            local cat = ParseEntityCategory(cons.AdjacencyCategory)
            local radius = (cons.AdjacencyDistance or 50)
            if not pos or not pos then
                coroutine.yield(1)
                self:PlatoonDisband()
                return
            end
            reference  = AIUtils.GetOwnUnitsAroundPointSorian(aiBrain, cat, pos, radius, cons.ThreatMin,
                                                        cons.ThreatMax, cons.ThreatRings, 'Overall', cons.MinRadius or 0)
            buildFunction = AIBuildStructures.AIBuildAdjacencySorian
            table.insert(baseTmplList, baseTmpl)
        else
            table.insert(baseTmplList, baseTmpl)
            relative = true
            reference = true
            buildFunction = AIBuildStructures.AIExecuteBuildStructureSorian
        end
        if cons.BuildClose then
            closeToBuilder = eng
        end
        if cons.BuildStructures[1] == 'T1Resource' or cons.BuildStructures[1] == 'T2Resource' or cons.BuildStructures[1] == 'T3Resource' then
            relative = true
            closeToBuilder = eng
            local guards = eng:GetGuards()
            for k,v in guards do
                if not v.Dead and v.PlatoonHandle and aiBrain:PlatoonExists(v.PlatoonHandle) and EntityCategoryContains(categories.CONSTRUCTION, v) then
                    v.PlatoonHandle:PlatoonDisband()
                end
            end
        end

        --LOG("*AI DEBUG: Setting up Callbacks for " .. eng.Sync.id)
        self.SetupEngineerCallbacksSorian(eng)

        -------- BUILD BUILDINGS HERE --------
        for baseNum, baseListData in baseTmplList do
            for k, v in cons.BuildStructures do
                if aiBrain:PlatoonExists(self) then
                    if not eng.Dead then
                        local faction = SUtils.GetEngineerFaction(eng)
                        if aiBrain.CustomUnits[v] and aiBrain.CustomUnits[v][faction] then
                            local replacement = SUtils.GetTemplateReplacement(aiBrain, v, faction, buildingTmpl)
                            if replacement then
                                buildFunction(aiBrain, eng, v, closeToBuilder, relative, replacement, baseListData, reference, cons.NearMarkerType)
                            else
                                buildFunction(aiBrain, eng, v, closeToBuilder, relative, buildingTmpl, baseListData, reference, cons.NearMarkerType)
                            end
                        else
                            buildFunction(aiBrain, eng, v, closeToBuilder, relative, buildingTmpl, baseListData, reference, cons.NearMarkerType)
                        end
                    else
                        if aiBrain:PlatoonExists(self) then
                            coroutine.yield(1)
                            self:PlatoonDisband()
                            return
                        end
                    end
                end
            end
        end

        -- wait in case we're still on a base
        if not eng.Dead then
            local count = 0
            while eng:IsUnitState('Attached') and count < 2 do
                coroutine.yield(60)
                count = count + 1
            end
        end

        if not eng.Dead and not eng:IsUnitState('Building') then
            return self.ProcessBuildCommandSorian(eng, false)
        end
    end,

    ---@param eng EngineerBuilder
    SetupEngineerCallbacksSorian = function(eng)
        if eng and not eng.Dead and not eng.BuildDoneCallbackSet and eng.PlatoonHandle and eng:GetAIBrain():PlatoonExists(eng.PlatoonHandle) then
            import("/lua/scenariotriggers.lua").CreateUnitBuiltTrigger(eng.PlatoonHandle.EngineerBuildDoneSorian, eng, categories.ALLUNITS)
            eng.BuildDoneCallbackSet = true
        end
        if eng and not eng.Dead and not eng.CaptureDoneCallbackSet and eng.PlatoonHandle and eng:GetAIBrain():PlatoonExists(eng.PlatoonHandle) then
            import("/lua/scenariotriggers.lua").CreateUnitStopCaptureTrigger(eng.PlatoonHandle.EngineerCaptureDoneSorian, eng)
            eng.CaptureDoneCallbackSet = true
        end
        if eng and not eng.Dead and not eng.ReclaimDoneCallbackSet and eng.PlatoonHandle and eng:GetAIBrain():PlatoonExists(eng.PlatoonHandle) then
            import("/lua/scenariotriggers.lua").CreateUnitStopReclaimTrigger(eng.PlatoonHandle.EngineerReclaimDoneSorian, eng)
            eng.ReclaimDoneCallbackSet = true
        end
        if eng and not eng.Dead and not eng.FailedToBuildCallbackSet and eng.PlatoonHandle and eng:GetAIBrain():PlatoonExists(eng.PlatoonHandle) then
            import("/lua/scenariotriggers.lua").CreateOnFailedToBuildTrigger(eng.PlatoonHandle.EngineerFailedToBuildSorian, eng)
            eng.FailedToBuildCallbackSet = true
        end
    end,

    ---@param eng EngineerBuilder
    RemoveEngineerCallbacksSorian = function(eng)
        if eng.BuildDoneCallbackSet then
            import("/lua/scenariotriggers.lua")RemoveUnitTrigger(eng, eng.PlatoonHandle.EngineerBuildDoneSorian)
            eng.BuildDoneCallbackSet = false
        end
        if eng.CaptureDoneCallbackSet then
            import("/lua/scenariotriggers.lua")RemoveUnitTrigger(eng, eng.PlatoonHandle.EngineerCaptureDoneSorian)
            eng.CaptureDoneCallbackSet = false
        end
        if eng.ReclaimDoneCallbackSet then
            import("/lua/scenariotriggers.lua")RemoveUnitTrigger(eng, eng.PlatoonHandle.EngineerReclaimDoneSorian)
            eng.ReclaimDoneCallbackSet = false
        end
        if eng.FailedToBuildCallbackSet then
            import("/lua/scenariotriggers.lua")RemoveUnitTrigger(eng, eng.PlatoonHandle.EngineerFailedToBuildSorian)
            eng.FailedToBuildCallbackSet = false
        end
    end,

    --- Callback functions for EngineerBuildAI
    ---@param unit Unit
    ---@param params any
    EngineerBuildDoneSorian = function(unit, params)
        if not unit.PlatoonHandle then return end
        if not unit.PlatoonHandle.PlanName == 'EngineerBuildAISorian' then return end
        --LOG("*AI DEBUG: Build done " .. unit.Sync.id)
        if not unit.ProcessBuild then
            unit.ProcessBuild = unit:ForkThread(unit.PlatoonHandle.ProcessBuildCommandSorian, true)
            unit.ProcessBuildDone = true
        end
    end,

    ---@param unit Unit
    ---@param params any
    EngineerCaptureDoneSorian = function(unit, params)
        if not unit.PlatoonHandle then return end
        if not unit.PlatoonHandle.PlanName == 'EngineerBuildAISorian' then return end
        --LOG("*AI DEBUG: Capture done" .. unit.Sync.id)
        if not unit.ProcessBuild then
            unit.ProcessBuild = unit:ForkThread(unit.PlatoonHandle.ProcessBuildCommandSorian, false)
        end
    end,

    ---@param unit Unit
    ---@param params any
    EngineerReclaimDoneSorian = function(unit, params)
        if not unit.PlatoonHandle then return end
        if not unit.PlatoonHandle.PlanName == 'EngineerBuildAISorian' then return end
        --LOG("*AI DEBUG: Reclaim done" .. unit.Sync.id)
        if not unit.ProcessBuild then
            unit.ProcessBuild = unit:ForkThread(unit.PlatoonHandle.ProcessBuildCommandSorian, false)
        end
    end,

    ---@param unit Unit
    ---@param params any
    EngineerFailedToBuildSorian = function(unit, params)
        if not unit.PlatoonHandle then return end
        if not unit.PlatoonHandle.PlanName == 'EngineerBuildAISorian' then return end
        if unit.ProcessBuildDone and unit.ProcessBuild then
            KillThread(unit.ProcessBuild)
            unit.ProcessBuild = nil
        end
        if not unit.ProcessBuild then
            unit.ProcessBuild = unit:ForkThread(unit.PlatoonHandle.ProcessBuildCommandSorian, false)
        end
    end,

    ---## Function: WatchForNotBuildingSorian
    --- After we try to build something, watch the engineer to
    --- make sure that the build goes through.  If not,
    --- try the next thing in the queue
    ---@param eng EngineerBuilder
    WatchForNotBuildingSorian = function(eng)
        WaitTicks(5)
        local aiBrain = eng:GetAIBrain()
        local engLastPos = false
        local stuckCount = 0
        while not eng.Dead and (eng.GoingHome or eng.Upgrading or eng.Fighting or eng:IsUnitState("Building") or
                  eng:IsUnitState("Attacking") or eng:IsUnitState("Repairing") or eng:IsUnitState("WaitingForTransport") or
                  eng:IsUnitState("Reclaiming") or eng:IsUnitState("Capturing") or eng:IsUnitState("Moving") or eng:IsUnitState("Enhancing") or eng:IsUnitState("Upgrading") or eng.ProcessBuild != nil
                  or eng.UnitBeingBuiltBehavior) do

            WaitSeconds(3)
            local engPos = eng:GetPosition()
            if not eng.Dead and engLastPos and eng:IsUnitState("Building") and not eng:IsUnitState("Capturing") and not eng:IsUnitState("Reclaiming")
            and not eng:IsUnitState("Repairing") and eng:GetWorkProgress() == 0 and VDist2Sq(engLastPos[1], engLastPos[3], engPos[1], engPos[3]) < 1 then
                if stuckCount > 10 then
                    stuckCount = 0
                    eng.NotBuildingThread = nil
                    eng.ProcessBuild = eng:ForkThread(eng.PlatoonHandle.ProcessBuildCommandSorian, true)
                    return
                else
                    stuckCount = stuckCount + 1
                end
            else
                stuckCount = 0
            end
            engLastPos = engPos
            --if eng.CDRHome then eng:PrintCommandQueue() end
        end
        eng.NotBuildingThread = nil
        if not eng.Dead and eng:IsIdleState() and not table.empty(eng.EngineerBuildQueue) and eng.PlatoonHandle then
            eng.PlatoonHandle.SetupEngineerCallbacksSorian(eng)
            if not eng.ProcessBuild then
                eng.ProcessBuild = eng:ForkThread(eng.PlatoonHandle.ProcessBuildCommandSorian, true)
            end
        end
    end,

    ---## Function: ProcessBuildCommandSorian
    --- Run after every build order is complete/fails.  Sets up the next
    --- build order in queue, and if the engineer has nothing left to do
    --- will return the engineer back to the army pool by disbanding the
    --- the platoon.  Support function for EngineerBuildAI
    ---@param eng EngineerManager
    ---@param removeLastBuild boolean
    ProcessBuildCommandSorian = function(eng, removeLastBuild)
        if not eng or eng.Dead or not eng.PlatoonHandle or eng:IsUnitState("Enhancing") or eng:IsUnitState("Upgrading") or eng.Upgrading or eng.GoingHome or eng.Fighting or eng.UnitBeingBuiltBehavior then
            if eng then eng.ProcessBuild = nil end
            return
        end
        local aiBrain = eng.PlatoonHandle:GetBrain()

        if not aiBrain or eng.Dead or not eng.EngineerBuildQueue or table.empty(eng.EngineerBuildQueue) then
            if aiBrain:PlatoonExists(eng.PlatoonHandle) then
                --LOG("*AI DEBUG: Disbanding Engineer Platoon in ProcessBuildCommand " .. eng.Sync.id)
                --if EntityCategoryContains(categories.COMMAND, eng) then
                --  LOG("*AI DEBUG: Commander Platoon Disbanded in ProcessBuildCommand")
                --end
                eng.PlatoonHandle:PlatoonDisband()
            end
            if eng then eng.ProcessBuild = nil end
            return
        end

        -- it wasn't a failed build, so we just finished something
        if removeLastBuild then
            table.remove(eng.EngineerBuildQueue, 1)
        end

        function BuildToNormalLocation(location)
            return {location[1], 0, location[2]}
        end

        function NormalToBuildLocation(location)
            return {location[1], location[3], 0}
        end

        eng.ProcessBuildDone = false
        IssueClearCommands({eng})
        local commandDone = false
        while not eng.Dead and not commandDone and not table.empty(eng.EngineerBuildQueue) do
            local whatToBuild = eng.EngineerBuildQueue[1][1]
            local buildLocation = BuildToNormalLocation(eng.EngineerBuildQueue[1][2])
            local buildRelative = eng.EngineerBuildQueue[1][3]
            local threadStarted = false
            -- see if we can move there first
            if AIUtils.EngineerMoveWithSafePathSorian(aiBrain, eng, buildLocation) then
                if not eng or eng.Dead or not eng.PlatoonHandle or not aiBrain:PlatoonExists(eng.PlatoonHandle) then
                    if eng then eng.ProcessBuild = nil end
                    return
                end
                -- check to see if we need to reclaim or capture...
                if not AIUtils.EngineerTryReclaimCaptureAreaSorian(aiBrain, eng, buildLocation) then
                    -- check to see if we can repair
                    if not AIUtils.EngineerTryRepairSorian(aiBrain, eng, whatToBuild, buildLocation) then
                        -- otherwise, go ahead and build the next structure there
                        aiBrain:BuildStructure(eng, whatToBuild, NormalToBuildLocation(buildLocation), buildRelative)
                        if not eng.NotBuildingThread then
                            threadStarted = true
                            eng.NotBuildingThread = eng:ForkThread(eng.PlatoonHandle.WatchForNotBuildingSorian)
                        end
                    end
                end
                if not threadStarted and not eng.NotBuildingThread then
                    eng.NotBuildingThread = eng:ForkThread(eng.PlatoonHandle.WatchForNotBuildingSorian)
                end
                commandDone = true
            else
                -- we can't move there, so remove it from our build queue
                table.remove(eng.EngineerBuildQueue, 1)
            end
        end

        -- final check for if we should disband
        if not eng or eng.Dead or table.empty(eng.EngineerBuildQueue) then
            if eng.PlatoonHandle and aiBrain:PlatoonExists(eng.PlatoonHandle) then
                --LOG("*AI DEBUG: Disbanding Engineer Platoon in ProcessBuildCommand " .. eng.Sync.id)
                --if EntityCategoryContains(categories.COMMAND, eng) then
                --  LOG("*AI DEBUG: Commander Platoon Disbanded in ProcessBuildCommand")
                --end
                eng.PlatoonHandle:PlatoonDisband()
            end
            if eng then eng.ProcessBuild = nil end
            return
        end
        if eng then eng.ProcessBuild = nil end
    end,

    ---@param self Platoon
    ---@param planName string
    ---@param radius number
    ---@param fullrestart boolean
    MergeWithNearbyPlatoonsSorian = function(self, planName, radius, fullrestart)
        -- check to see we're not near an ally base
        local aiBrain = self:GetBrain()
        if not aiBrain then
            return
        end

        if self.UsingTransport then
            return
        end

        local platPos = self:GetPlatoonPosition()
        if not platPos then
            return
        end

        local radiusSq = radius*radius
        -- if we're too close to a base, forget it
        if aiBrain.BuilderManagers then
            for baseName, base in aiBrain.BuilderManagers do
                local baseRadius = base.FactoryManager.Radius
                if VDist2Sq(platPos[1], platPos[3], base.Position[1], base.Position[3]) <= (baseRadius * baseRadius) + (3 * radiusSq) then
                    return
                end
            end
        end

        AlliedPlatoons = aiBrain:GetPlatoonsList()
        local bMergedPlatoons = false
        for _,aPlat in AlliedPlatoons do
            if aPlat:GetPlan() != planName then
                continue
            end
            if aPlat == self then
                continue
            end
            if aPlat.UsingTransport then
                continue
            end

            local allyPlatPos = aPlat:GetPlatoonPosition()
            if not allyPlatPos or not aiBrain:PlatoonExists(aPlat) then
                continue
            end

            AIAttackUtils.GetMostRestrictiveLayer(self)
            AIAttackUtils.GetMostRestrictiveLayer(aPlat)

            -- make sure we're the same movement layer type to avoid hamstringing air of amphibious
            if self.MovementLayer != aPlat.MovementLayer then
                continue
            end

            if VDist2Sq(platPos[1], platPos[3], allyPlatPos[1], allyPlatPos[3]) <= radiusSq then
                local units = aPlat:GetPlatoonUnits()
                local validUnits = {}
                local bValidUnits = false
                for _,u in units do
                    if not u.Dead and not u:IsUnitState('Attached') then
                        table.insert(validUnits, u)
                        bValidUnits = true
                    end
                end
                if not bValidUnits then
                    continue
                end
                --LOG("*AI DEBUG: Merging platoons " .. self.BuilderName .. ": (" .. platPos[1] .. ", " .. platPos[3] .. ") and " .. aPlat.BuilderName .. ": (" .. allyPlatPos[1] .. ", " .. allyPlatPos[3] .. ")")
                aiBrain:AssignUnitsToPlatoon(self, validUnits, 'Attack', 'GrowthFormation')
                bMergedPlatoons = true
            end
        end
        if bMergedPlatoons then
            if fullrestart then
                self:Stop()
                self:SetAIPlan(planName)
            else
                self:StopAttack()
            end
        end
    end,

    ---Modified version of AvoidsBases() that checks for and avoids ally bases
    ---@param self Platoon
    ---@param markerPos Vector
    ---@param avoidBasesDefault any
    ---@param baseRadius number
    ---@return boolean
    AvoidsBasesSorian = function(self, markerPos, avoidBasesDefault, baseRadius)
        if not avoidBasesDefault then
            return true
        end

        local aiBrain = self:GetBrain()

        for baseName, base in aiBrain.BuilderManagers do
            local avoidDist = VDist2Sq(base.Position[1], base.Position[3], markerPos[1], markerPos[3])
            if avoidDist < baseRadius * baseRadius then
                return false
            end
        end
        for k,v in ArmyBrains do
            if not v:IsDefeated() and not ArmyIsCivilian(v:GetArmyIndex()) and IsAlly(v:GetArmyIndex(), aiBrain:GetArmyIndex()) then
                local startX, startZ = v:GetArmyStartPos()
                if VDist2Sq(markerPos[1], markerPos[3], startX, startZ) < baseRadius * baseRadius then
                    return false
                end
            end
        end
        return true
    end,

    ---@param self Platoon
    NameUnitsSorian = function(self)
        local units = self:GetPlatoonUnits()
        local AINames = import("/lua/ai/sorianlang.lua").AINames
        if units and not table.empty(units) then
            for k, v in units do
                local ID = v.UnitId
                if AINames[ID] then
                    local num = Random(1, table.getn(AINames[ID]))
                    v:SetCustomName(AINames[ID][num])
                end
            end
        end
    end,

}