OldExecutePlanFunctionUveso = ExecutePlan
function ExecutePlan(aiBrain)
    if not aiBrain.Sorian then
        OldExecutePlanFunctionUveso(aiBrain)
        return
    end
    aiBrain:SetConstantEvaluate(false)
    local behaviors = import("/lua/ai/aibehaviors.lua")
    WaitSeconds(1)
    if not aiBrain.BuilderManagers.MAIN.FactoryManager:HasBuilderList() then
        aiBrain:SetResourceSharing(true)
        aiBrain:SetupUnderEnergyStatTrigger(0.1)
        aiBrain:SetupUnderMassStatTrigger(0.1)

        SetupMainBase(aiBrain)

        -- Get units out of pool and assign them to the managers
        local mainManagers = aiBrain.BuilderManagers.MAIN

        local pool = aiBrain:GetPlatoonUniquelyNamed('ArmyPool')
        for k,v in pool:GetPlatoonUnits() do
            if EntityCategoryContains(categories.ENGINEER, v) then
                mainManagers.EngineerManager:AddUnit(v)
            elseif EntityCategoryContains(categories.FACTORY * categories.STRUCTURE, v) then
                mainManagers.FactoryManager:AddFactory(v)
            end
        end

        aiBrain:ForkThread(UnitCapWatchThreadSorian)
        aiBrain:ForkThread(behaviors.NukeCheck)

    end
    if aiBrain.PBM then
        aiBrain:PBMSetEnabled(false)
    end
end

---@param aiBrain AIBrain
function UnitCapWatchThreadSorian(aiBrain)
    --LOG('*AI DEBUG: UnitCapWatchThreadSorian started')
    while true do
        WaitTicks(301)
        if GetArmyUnitCostTotal(aiBrain:GetArmyIndex()) > (GetArmyUnitCap(aiBrain:GetArmyIndex()) - 20) then
            local underCap = false

            -- More than 1 T3 Power	  ----(aiBrain, number of units to check for, category of units to check for, category of units to kill off)
            underCap = GetAIUnderUnitCap(aiBrain, 1, categories.TECH3 * categories.ENERGYPRODUCTION * categories.STRUCTURE, categories.TECH1 * categories.ENERGYPRODUCTION * categories.STRUCTURE * categories.DRAGBUILD)

            -- More than 9 T2/T3 Defense - shields
            if underCap ~= true then
                underCap = GetAIUnderUnitCap(aiBrain, 9, (categories.TECH2 + categories.TECH3) * categories.DEFENSE * categories.STRUCTURE - categories.SHIELD, categories.TECH1 * categories.DEFENSE * categories.STRUCTURE)
            end

            -- More than 6 T2/T3 Engineers
            if underCap ~= true then
                underCap = GetAIUnderUnitCap(aiBrain, 6, categories.ENGINEER * (categories.TECH2 + categories.TECH3), categories.TECH1 * categories.ENGINEER - categories.POD)
            end

            -- More than 9 T3 Engineers/SCUs
            if underCap ~= true then
                underCap = GetAIUnderUnitCap(aiBrain, 9, categories.ENGINEER * categories.TECH3 + categories.SUBCOMMANDER, categories.TECH2 * categories.ENGINEER - categories.ENGINEERSTATION)
            end

            -- More than 24 T3 Land Units minus Engineers
            if underCap ~= true then
                underCap = GetAIUnderUnitCap(aiBrain, 24, categories.TECH3 * categories.MOBILE * categories.LAND - categories.ENGINEER, categories.TECH1 * categories.MOBILE * categories.LAND)
            end

            -- More than 9 T3 Air Units minus Scouts
            if underCap ~= true then
                underCap = GetAIUnderUnitCap(aiBrain, 9, categories.TECH3 * categories.MOBILE * categories.AIR - categories.INTELLIGENCE, categories.TECH1 * categories.MOBILE * categories.AIR - categories.SCOUT - categories.POD)
            end

            -- More than 9 T3 AntiAir
            if underCap ~= true then
                underCap = GetAIUnderUnitCap(aiBrain, 9, categories.TECH3 * categories.DEFENSE * categories.ANTIAIR, categories.TECH2 * categories.DEFENSE * categories.ANTIAIR)
            end
        end
    end
end
