--[[
    BigGaren
]]





if Player.CharName ~= "Garen" then
    return false
end

module("BGaren", package.seeall, log.setup)
clean.module("BGaren", package.seeall, log.setup)



-- Globals
local CoreEx = _G.CoreEx
local Libs = _G.Libs
local os_clock = _G.os.clock
local Menu = Libs.NewMenu
local Prediction = Libs.Prediction
local HealthPred = _G.Libs.HealthPred
local DetectedSpell
local DashLib = _G.Libs.DashLib
local Orbwalker = Libs.Orbwalker
local CollisionLib = Libs.CollisionLib
local DamageLib = Libs.DamageLib
local ImmobileLib = Libs.ImmobileLib
local SpellLib = Libs.Spell
local TS = Libs.TargetSelector()
local HealthPrediction = Libs.HealthPred
local ObjectManager = CoreEx.ObjectManager
local EventManager = CoreEx.EventManager
local Input = CoreEx.Input
local Enums = CoreEx.Enums
local Game = CoreEx.Game
local Geometry = CoreEx.Geometry
local Renderer = CoreEx.Renderer
local Evade = _G.CoreEx.EvadeAPI
local SpellSlots = Enums.SpellSlots
local SpellStates = Enums.SpellStates
local BuffTypes = Enums.BuffTypes
local Events = Enums.Events
local HitChance = Enums.HitChance
local HitChanceStrings = { "Collision", "OutOfRange", "VeryLow", "Low", "Medium", "High", "VeryHigh", "Dashing", "Immobile" };

local LocalPlayer = ObjectManager.Player.AsHero

-- Check if we are using the right champion




local flashSpell = nil
-- Check if Player has flash
if string.find(string.lower(LocalPlayer:GetSpell(SpellSlots.Summoner1).Name), "flash") then
    flashSpell = SpellSlots.Summoner1
elseif string.find(string.lower(LocalPlayer:GetSpell(SpellSlots.Summoner2).Name), "flash") then
    flashSpell = SpellSlots.Summoner2
end








-- Globals
local Garen = {}
local Utils = {}

Garen.TargetSelector = nil
Garen.Logic = {}

local UsableSS = {
    Ignite = {
        Slot = nil,
        Range = 600
    },

    Flash = {
        Slot = nil,
        Range = 400
    }
}

function CheckIgniteSlot()
    local slots = { Enums.SpellSlots.Summoner1, Enums.SpellSlots.Summoner2 }

    local function IsIgnite(slot)
        return LocalPlayer:GetSpell(slot).Name == "SummonerDot"
    end

    for _, slot in ipairs(slots) do
        if IsIgnite(slot) then
            if UsableSS.Ignite.Slot ~= slot then
                UsableSS.Ignite.Slot = slot
            end

            return
        end
    end

    if UsableSS.Ignite.Slot ~= nil then
        UsableSS.Ignite.Slot = nil
    end

end

function CheckFlashSlot()
    local slots = { Enums.SpellSlots.Summoner1, Enums.SpellSlots.Summoner2 }

    local function IsFlash(slot)
        return LocalPlayer:GetSpell(slot).Name == "SummonerFlash"
    end

    for _, slot in ipairs(slots) do
        if IsFlash(slot) then
            if UsableSS.Flash.Slot ~= slot then
                UsableSS.Flash.Slot = slot
            end

            return
        end
    end

    if UsableSS.Flash.Slot ~= nil then
        UsableSS.Flash.Slot = nil
    end

end
-- Spells
Garen.Q = SpellLib.Active({
    Slot = SpellSlots.Q,
    Range = 300,

})

Garen.W = SpellLib.Active({
    Slot = SpellSlots.W,

})

Garen.E = SpellLib.Active({
    Slot = SpellSlots.E,
    Range = 325,
})

Garen.R = SpellLib.Targeted({
    Slot = SpellSlots.R,
    Range = 400,
    Delay = 0.435,
    Type = "Targeted",


})


-- Utils


local CastSpell = function(slot, position, condition)
    local tick = os_clock()
    if LastCastT[slot] + 0.1 < tick then
        if Input.Cast(slot, position) then
            LastCastT[slot] = tick
            if condition ~= nil then
                return true and (type(condition) == "function" and condition() or type(condition) == "boolean" and condition)
            end
            return true
        end
    end
    return false
end

function Utils.GetEBonusRange ()


    local ultLevel = Garen.R:GetLevel()

    if ultLevel == 0 then
        return 0
    end

    local stacks = Utils.addStackRange()

    local rangeModifier = ({ 4.5, 6, 7.5 })[Garen.R:GetLevel()]

    local rangeAdded = stacks * rangeModifier

    if rangeAdded >= 75 then
        return 75
    end

    return rangeAdded

end
function Utils.addStackRange()

    local buffs = LocalPlayer.Buffs

    for k, v in pairs(buffs) do

        if (v.Name == "Feast") then


            return v.Count

        end


    end

    return 0

end

function getUltDmg(Target)

    if not Garen.R:IsLearned() then
        return 0
    end
    if not Garen.R:IsReady() then
        return 0
    end

    if Target == nil then
        return
    end

    local dmgR = ({ 150, 300, 450 })[LocalPlayer:GetSpell(SpellSlots.R).Level]
    local rModifier = ({ 25, 30, 35 })[LocalPlayer:GetSpell(SpellSlots.R).Level]

    local bonusDmg = (Target.MaxHealth - Target.Health) / 100 * rModifier

    return dmgR + bonusDmg

end

function getIgniteDmg(target)


    if not UsableSS.Ignite.Slot ~= nil and LocalPlayer:GetSpellState(UsableSS.Ignite.Slot) ==
            Enums.SpellStates.Ready then

        return 50 + (20 * LocalPlayer.Level) - target.HealthRegen * 2.5

    end

    return 0


end

function getWDmg(Target)

    if not Garen.W:IsLearned() then
        return 0

    end

    if not Garen.W:IsReady() then
        return 0

    end

    local baseDmg = ({ 75, 125, 175, 225, 275 })[Garen.W:GetLevel()]

    local apDmg = LocalPlayer.TotalAP * 0.7

    local totalDmg = baseDmg + apDmg

    return DamageLib.CalculateMagicalDamage(LocalPlayer, Target, totalDmg)


end
function GetEDamage(target)

    if not Garen.E:IsLearned() then
        return 0
    end

    local physicalBaseDamagePerSpin = ({ 4, 8, 12, 16, 20 })[Garen.E:GetLevel()]
    local physicalBonusDamagePerLevel = ({ 0, 0.8, 1.6, 2.4, 3.2, 4, 4.8, 5.6, 6.4, 6.6, 6.8, 7, 7.2, 7.4, 7.6, 7.6, 8, 8.2 })[LocalPlayer.Level]
    local adValueBonus = ({ 32, 34, 36, 38, 40 })[Garen.E:GetLevel()]

    local extraspins = 0

    local attackSpeedMod = LocalPlayer.AttackSpeedMod

    if attackSpeedMod < 1.25 then
        extraspins = 0
    elseif attackSpeedMod >= 1.25 and attackSpeedMod < 1.5 then
        extraspins = 1
    elseif attackSpeedMod >= 1.5 and attackSpeedMod < 1.75 then
        extraspins = 2
    elseif attackSpeedMod >= 1.75 and attackSpeedMod < 2 then
        extraspins = 3
    elseif attackSpeedMod >= 2 and attackSpeedMod < 2.25 then
        extraspins = 4
    elseif attackSpeedMod >= 1.75 and attackSpeedMod < 2 then
        extraspins = 5
    elseif attackSpeedMod >= 2 and attackSpeedMod < 2.25 then
        extraspins = 6
    elseif attackSpeedMod >= 2.25 and attackSpeedMod < 2.5 then
        extraspins = 7
    end

    local amountOfSpins = 7 + extraspins

return ((physicalBaseDamagePerSpin + physicalBonusDamagePerLevel + (LocalPlayer.TotalAD * (adValueBonus / 100)))*amountOfSpins  )*1.25

end
function getQDmg(Target)

    if not Garen.Q:IsLearned() then
        return 0

    end

    if not Garen.Q:IsReady() then
        return 0

    end

    local baseDmg = ({ 30, 60, 90, 120, 150 })[Garen.Q:GetLevel()]

    local adDmg = LocalPlayer.TotalAD

    local totalDmg = baseDmg + adDmg * 1.5

    return DamageLib.CalculatePhysicalDamage(LocalPlayer, Target, totalDmg)


end

function getUltMinionDmg()

    local dmgR = 1000
    local bonusDmg = LocalPlayer.TotalAP / 2 + LocalPlayer.BonusHealth / 10

    return dmgR + bonusDmg

end

function Utils.IsGameAvailable()
    -- Is game available to automate stuff
    return not (Game.IsChatOpen() or Game.IsMinimized() or LocalPlayer.IsDead)
end
function Utils.IsInRange(From, To, Min, Max)
    -- Is Target in range
    local Distance = From:Distance(To)
    return Distance > Min and Distance <= Max
end
function Utils.GetBoundingRadius(Target)
    if not Target then
        return 0
    end

    -- Bounding boxes
    return LocalPlayer.BoundingRadius + Target.BoundingRadius
end
function Utils.IsValidTarget(Target)
    return Target and Target.IsTargetable and Target.IsAlive
end

function Utils.CountMinionsInRange(range, type)
    local amount = 0
    for k, v in ipairs(ObjectManager.GetNearby(type, "minions")) do
        local minion = v.AsMinion
        if not minion.IsJunglePlant and minion.IsValid and not minion.IsDead and minion.IsTargetable and
                LocalPlayer:Distance(minion) < range then
            amount = amount + 1
        end
    end
    return amount
end

function Utils.CountMonstersInRange(range, type)
    local amount = 0
    for k, v in ipairs(ObjectManager.GetNearby(type, "minions")) do
        local minion = v.AsMinion
        if not minion.IsJunglePlant and minion.IsValid and not minion.IsDead and minion.IsTargetable and
                LocalPlayer:Distance(minion) < range then
            amount = amount + 1
        end
    end
    return amount
end

function Utils.ValidMinion(minion)
    return minion and minion.IsTargetable and minion.MaxHealth > 6 -- check if not plant or shroom
end
function Utils.TargetsInRange(Target, Range, Team, Type, Condition)
    -- return target in range
    local Objects = ObjectManager.Get(Team, Type)
    local Array = {}
    local Index = 0

    for _, Object in pairs(Objects) do
        if Object and Object ~= Target then
            Object = Object.AsAI
            if
            Utils.IsValidTarget(Object) and
                    (not Condition or Condition(Object))
            then
                local Distance = Target:Distance(Object.Position)
                if Distance <= Range then
                    Array[Index] = Object
                    Index = Index + 1
                end
            end
        end
    end

    return { Array = Array, Count = Index }
end

function Garen.Logic.W(Target, Enable, HitChance)


end
function Garen.Logic.Q(Target, Hitchance, Enable, Auto)


end
function Garen.Logic.E(Target, Enable)

end
function Garen.Logic.R(Target, Enable, EnableFlash)


    if Enable and EnableFlash and flashSpell ~= nil and Utils.IsInRange(LocalPlayer.Position, Target.Position, 410, 400 + 375) then


        if Garen.R:IsReady() and LocalPlayer:GetSpellState(UsableSS.Flash.Slot) == Enums.SpellStates.Ready then

            Input.Cast(flashSpell, Target.Position)

        end


    end

    Input.Cast(Garen.R.Slot, Target)

    return false
end

function Garen.Logic.Waveclear()


    local garenEState = Garen.E:GetName()

    if Menu.Get("Wave.Q.Use") and Garen.Q:IsReady() and Garen.Q:IsLearned() then

        local cannon = nil

        local minionList = ObjectManager.GetNearby("enemy", "minions")

        for k, v in pairs(minionList) do

            if v.AsAI.IsSiegeMinion then
                cannon = v
            end
        end

        if cannon ~= nil then

            local cannonFutureHealth = (HealthPred.GetHealthPrediction(cannon, 0.4))

            if getQDmg(cannon) >= cannonFutureHealth and Utils.IsInRange(LocalPlayer.Position, cannon.Position, 0, 150) then

                Orbwalker.Attack(cannon)
                if garenEState == "GarenECancel" then


                    print("castin q because cannon about to die!")
                    Input.Cast(SpellSlots.E)
                    Orbwalker.Attack(cannon)
                    Input.Cast(SpellSlots.Q)
                    return true
                end

                Orbwalker.Attack(cannon)
                Input.Cast(SpellSlots.Q)
                print("castin q because cannon about to die!")
                return true
            end
        end
    end

    if Menu.Get("Wave.E.Use") and garenEState ~= "GarenECancel" and Garen.E:IsReady() and Garen.E:IsLearned() then


        if Utils.CountMinionsInRange(Garen.E.Range, "enemy") >= Menu.Get("Wave.E.HitCount") then

            print("Casting E because more then " .. Menu.Get("Wave.E.HitCount") .. "minions are in E range!!")
            Input.Cast(SpellSlots.E)
            return true
        end
    end

    if Utils.CountMonstersInRange(200, "all") >= 1 then

        if garenEState ~= "GarenECancel" and Garen.E:IsReady() and Garen.E:IsLearned() then

            if Utils.CountMonstersInRange(Garen.E.Range, "neutral") >= 1 then

                print("Casting E because jungle creeps are near! ")
                Input.Cast(SpellSlots.E)
                Input.Cast(SpellSlots.Q)

                return true
            end
        end

        return true
    end
end

function Garen.Logic.Harass()


end

function Garen.Logic.Combo()



    local hasQBuff = false

    for k, v in pairs(LocalPlayer.Buffs) do


        if v.Name == "GarenQ" then
            hasQBuff = true
        end
    end

    local Target = TS:GetTarget(1000)

    if Target then


        if canKill(Target) and UsableSS.Ignite.Slot ~= nil and getIgniteDmg(Target) ~= 0 then
            Input.Cast(UsableSS.Ignite.Slot, Target)
        end

        if Garen.R:IsReady() and not Target.HasUndyingBuff and not Target.IsInvulnerable then

            if (Target.Health + Target.ShieldAll - getUltDmg(Target) <= 0) then


                Garen.Logic.R(Target, Menu.Get("Combo.R.Use"), Menu.Get("Combo.R.Flash.Use"))

                return true


            end

        end

        if Menu.Get("Combo.W.Use") then
            if Evade.GetDetectedSkillshots ~= nil and Evade.IsAboutToHit(0, LocalPlayer) then
                Garen.W:Cast()
                print("we did it!")
            end
        end

        if Menu.Get("Combo.Q.Engage") then

            if Garen.Q:IsReady() and not hasQBuff then

                Garen.Q:Cast()

                return true

            end

        end

        if Menu.Get("Combo.Q.Use") and Utils.IsInRange(LocalPlayer.Position, Target.Position, 0, LocalPlayer.BoundingRadius + 175 - Target.BoundingRadius)

                and not hasQBuff and Garen.Q:IsReady()

        then
            Garen.Q:Cast()
            return true
        end

        if Menu.Get("Combo.E.Use") and Utils.IsInRange(LocalPlayer.Position, Target.Position, 0, Garen.E.Range) then

            local garenEState = Garen.E:GetName()

            if Menu.Get("E.After.Q", "Hit Q before E if possible", true) then

                local hasQBuff = false

                for k, v in pairs(LocalPlayer.Buffs) do


                    if v.Name == "GarenQ" then
                        hasQBuff = true
                    end
                end

                if hasQBuff and Garen.E:IsReady() then
                    return true

                end

            end

            if garenEState ~= "GarenECancel" then

                if Garen.E:IsReady() then
                    Input.Cast(SpellSlots.E)
                end

                return true
            else
                Orbwalker.Attack(Target)
                return true
            end

            return false

        end

    end

end

function Garen.Logic.Flee()

    if Garen.Q:IsReady() then
        Input.Cast(SpellSlots.Q)
    end

end

function canKill(target)

    if not Menu.Get("Draw.ComboDamage") then
        return
    end

    local damageToDeal = 0

    local useIgnite = false

    if getIgniteDmg(target) ~= 0 then
        useIgnite = true
    end

    local useQ = Garen.Q:IsReady()
    local useE = false
    local useR = Garen.R:IsReady() and Menu.Get("Combo.R.Use")

    if useQ then

        damageToDeal = damageToDeal + getQDmg(target)
    end

    if useIgnite then
        damageToDeal = damageToDeal + getIgniteDmg(target)
    end

    if useR then
        damageToDeal = damageToDeal + getUltDmg(target)
    end

    return target.Health + target.ShieldAll - damageToDeal <= 0

end

function Garen.LoadMenu()
    Menu.RegisterMenu("BigGaren", "BigGaren", function()

        Menu.NewTree("BigGarenCombo", "Combo", function()

            Menu.Checkbox("Combo.Q.Use", "Cast Q", true)
            Menu.Checkbox("Combo.Q.Engage", "Use Q to Engage", true)
            Menu.Checkbox("E.After.Q", "Hit Q before E if possible", true)
            Menu.Checkbox("Combo.W.Use", "Cast W", false)
            Menu.Checkbox("Combo.E.Use", "Cast E", true)
            Menu.Checkbox("Combo.R.Use", "Cast R", true)
            Menu.Checkbox("Combo.R.Flash.Use", "Use Flash to R", true)

            Menu.NextColumn()
        end)

        Menu.NewTree("BigGarenWClear", "Waveclear", function()

            Menu.Checkbox("Wave.Q.Use", "Cast Q for cannon minion", true)
            Menu.Checkbox("Wave.E.Use", "Cast E", true)
            Menu.Slider("Wave.E.HitCount", "Minimum Minions Hit", 3, 1, 6, 1)

            Menu.NextColumn()
        end)

        Menu.NewTree("BigGarenAutoR", "Auto Settings", function()

            Menu.Checkbox("Auto.R.Hero", "Auto R killable champions in range", true)

        end)

        Menu.NewTree("Drawings", "Drawings", function()
            Menu.Checkbox("Drawings.E", "E", true)
            Menu.Checkbox("Drawings.R", "R", true)
            Menu.Checkbox("Draw.ComboDamage", "Draw Q + E + R + Ignite Damage", true)
            Menu.Checkbox("Drawings.Combo.OnlyR", "Only Draw R Damage", true)


        end)
    end)
end

function Garen.Logic.Auto()
    CheckIgniteSlot()
    CheckFlashSlot()
    for k, v in pairs(ObjectManager.GetNearby("enemy", "heroes")) do
        local enemy = v.AsHero

        local target = TS:GetTarget(Garen.R.Range, true)

        if target and not target.HasUndyingBuff then

            if target.Health + target.ShieldAll <= getUltDmg(target) and Menu.Get("Auto.R.Hero") then

                TS:ForceTarget(TS, target)
                Input.Cast(Garen.R.Slot, enemy)
                return true

            end


        end


    end

    if Evade.GetDangerousSkillshots ~= nil and Evade.IsAboutToHit(0.01, LocalPlayer) then
        Garen.W:Cast()
        print("we did it!")
    end


end

CheckIgniteSlot()

function Garen.OnDrawDamage(target, dmgList)


    if not Menu.Get("Draw.ComboDamage") and not Menu.Get("Drawings.Combo.OnlyR") then
        return
    end

    if Menu.Get("Drawings.Combo.OnlyR") and Garen.R:IsReady() then table.insert(dmgList, getUltDmg(target))
        return
        elseif Menu.Get("Drawings.Combo.OnlyR") and not Garen.R:IsReady() then return 0
    end

    local damageToDeal = 0

    local useIgnite = false

    if getIgniteDmg(target) ~= 0 then
        useIgnite = true
    end

    local useQ = Garen.Q:IsReady()
    local useE = Garen.E:IsReady()
    local useR = Garen.R:IsReady() and Menu.Get("Combo.R.Use")

    if useQ then

        damageToDeal = damageToDeal + getQDmg(target)
    end

    if useE then

        damageToDeal = damageToDeal + GetEDamage(target)
    end

    if useIgnite then
        damageToDeal = damageToDeal + getIgniteDmg(target)
    end

    if useR then

        damageToDeal = damageToDeal + getUltDmg(target)
    end




    table.insert(dmgList, damageToDeal)
end

function Garen.OnDraw()
    -- If player is not on screen than don't draw
    if not LocalPlayer.IsOnScreen then
        return false
    end ;

    -- Get spells ranges
    local Spells = { Q = Garen.Q, W = Garen.W, E = Garen.E, R = Garen.R }

    -- Draw them all

    if Menu.Get("Drawings.E") then
        Renderer.DrawCircle3D(LocalPlayer.Position, 325, 30, 1, 0xFF31FFFF)
    end

    if Menu.Get("Drawings.R") then
        Renderer.DrawCircle3D(LocalPlayer.Position, Garen.R.Range, 30, 1, 0xFF31FFFF)
    end


    return true
end

function Garen.OnTick()
    if not Utils.IsGameAvailable() then
        return false
    end

    local OrbwalkerMode = Orbwalker.GetMode()

    local OrbwalkerLogic = Garen.Logic[OrbwalkerMode]

    if OrbwalkerLogic then
        -- Calculate spell data

        -- Do logic
        if OrbwalkerLogic() then
            return true
        end
    end

    if Garen.Logic.Auto() then
        return true
    end

    return false

end

function OnLoad()

    INFO("Welcome to BigGaren, enjoy your stay")

    Garen.LoadMenu()
    for EventName, EventId in pairs(Events) do
        if Garen[EventName] then
            EventManager.RegisterCallback(EventId, Garen[EventName])
        end
    end

    return true

end