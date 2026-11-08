-- mining.lua
--
-- Layout at the starting position:
--   Fuel chest: directly LEFT, at turtle elevation.
--   Output chest: directly ABOVE.
--   Mining area: 15 x 15, extending FORWARD and RIGHT.
--
-- The starting position is above the first corner block.
-- Keep the entire travel layer clear.
--
-- Run once:    mining.lua once
-- Repeat:      mining.lua
--
-- Always start at home, facing the original direction.
-- Position tracking is not preserved across reboots.

local SIZE = 15
local REQUIRED_FUEL = 252 + 20
local PAUSE_SECONDS = 5

local args = { ... }
local RUN_ONCE = args[1] == "once"

-- Coordinates relative to home:
-- x: right
-- z: forward
-- dir: 0 forward, 1 right, 2 backward, 3 left
local x, z, dir = 0, 0, 0

local dx = {
    [0] = 0,
    [1] = 1,
    [2] = 0,
    [3] = -1
}

local dz = {
    [0] = 1,
    [1] = 0,
    [2] = -1,
    [3] = 0
}

local function fail(message)
    error(message, 0)
end

local function check(ok, reason)
    if not ok then
        fail(tostring(reason or "Turtle action failed"))
    end
end

local function face(target)
    while dir ~= target do
        if (target - dir) % 4 == 3 then
            check(turtle.turnLeft())
            dir = (dir + 3) % 4
        else
            check(turtle.turnRight())
            dir = (dir + 1) % 4
        end
    end
end

local function forward()
    local reason

    -- Retry briefly for temporary obstructions.
    for attempt = 1, 6 do
        local ok
        ok, reason = turtle.forward()

        if ok then
            -- Track only successful movements.
            x = x + dx[dir]
            z = z + dz[dir]
            return
        end

        if turtle.detect() then
            break
        end

        sleep(0.5)
    end

    -- Do not dig forward into equipment or other blocks.
    fail("Movement blocked: " .. tostring(reason))
end

local function moveTo(targetX, targetZ)
    if x ~= targetX then
        face(targetX > x and 1 or 3)

        while x ~= targetX do
            forward()
        end
    end

    if z ~= targetZ then
        face(targetZ > z and 0 or 2)

        while z ~= targetZ do
            forward()
        end
    end
end

local function goHome()
    -- Return through cells already visited during this pass.
    local edge = (x % 2 == 0) and 0 or (SIZE - 1)

    moveTo(x, edge)
    moveTo(0, edge)
    moveTo(0, 0)
    face(0)
end

local function requireChest(inspect, location)
    local ok, block = inspect()

    if not ok or (
        block.name ~= "minecraft:chest"
        and block.name ~= "minecraft:trapped_chest"
    ) then
        fail("Missing chest " .. location)
    end
end

local function unload()
    requireChest(turtle.inspectUp, "above home.")

    -- Face into the clear field if items must be discarded.
    -- Restore the previous direction afterward.
    local savedDir = dir
    face(0)

    local warned = false

    for slot = 1, 16 do
        if turtle.getItemCount(slot) > 0 then
            turtle.select(slot)

            while turtle.getItemCount(slot) > 0 do
                local before = turtle.getItemCount(slot)

                -- Deposit as much as possible above.
                turtle.dropUp()

                if turtle.getItemCount(slot) == before then
                    if not warned then
                        print("Output full; discarding remaining items.")
                        warned = true
                    end

                    turtle.dropDown()

                    -- If dropping below is blocked, try forward.
                    if turtle.getItemCount(slot) == before then
                        turtle.drop()
                    end
                end

                -- Never get stuck trying to unload.
                if turtle.getItemCount(slot) == before then
                    print("Could not empty slot " .. slot .. "; continuing.")
                    break
                end
            end
        end
    end

    face(savedDir)
end

local function emptySlot()
    -- Used only when collecting fuel.
    for slot = 1, 16 do
        if turtle.getItemCount(slot) == 0 then
            return slot
        end
    end
end

local function enoughFuel()
    local level = turtle.getFuelLevel()
    return level == "unlimited" or level >= REQUIRED_FUEL
end

local function ensureFuel()
    if enoughFuel() then
        return
    end

    local limit = turtle.getFuelLimit()

    if type(limit) == "number" and limit < REQUIRED_FUEL then
        fail("Configured fuel capacity is too low for this route.")
    end

    -- Consume any coal already carried first.
    for slot = 1, 16 do
        if enoughFuel() then
            return
        end

        local item = turtle.getItemDetail(slot)

        if item and item.name == "minecraft:coal" then
            turtle.select(slot)
            check(turtle.refuel())
        end
    end

    if enoughFuel() then
        return
    end

    face(3)
    requireChest(turtle.inspect, "on the left of home.")

    local collected = 0

    while not enoughFuel() and collected < 64 do
        local slot = emptySlot()

        if not slot then
            unload()
            slot = emptySlot()
        end

        if not slot then
            fail("Cannot make inventory space for coal.")
        end

        turtle.select(slot)

        local ok, reason = turtle.suck(64 - collected)

        if not ok then
            fail("Cannot collect coal: " .. tostring(reason))
        end

        local item = turtle.getItemDetail(slot)

        if not item or item.name ~= "minecraft:coal" then
            fail("The fuel chest must contain only coal.")
        end

        collected = collected + item.count
        check(turtle.refuel())
    end

    face(0)

    if not enoughFuel() then
        fail("Insufficient fuel after collecting up to 64 coal.")
    end
end

local function mineBelow()
    if not turtle.detectDown() then
        return
    end

    -- No slot changes or inventory checks here.
    -- Available slots fill automatically.
    -- Excess drops are left in the world if inventory is full.
    --
    -- Dig only once per visit so instant regeneration cannot
    -- trap the turtle in an endless digging loop.
    local ok, reason = turtle.digDown()

    if not ok and turtle.detectDown() then
        fail("Cannot mine below: " .. tostring(reason))
    end
end

local function mineArea()
    -- Keep this slot selected for the entire pass.
    turtle.select(1)

    for column = 0, SIZE - 1 do
        for position = 1, SIZE do
            mineBelow()

            if position < SIZE then
                forward()
            end
        end

        if column < SIZE - 1 then
            -- Shift right, then traverse the next column
            -- in the opposite direction.
            face(1)
            forward()
            face(column % 2 == 0 and 2 or 0)
        end
    end
end

local function main()
    local pass = 0

    while true do
        ensureFuel()
        unload()

        pass = pass + 1

        print(("Pass %d; fuel: %s"):format(
            pass,
            tostring(turtle.getFuelLevel())
        ))

        mineArea()
        goHome()
        unload()

        print("Home, original direction restored; pass complete.")

        if RUN_ONCE then
            return
        end

        sleep(PAUSE_SECONDS)
    end
end

local ok, reason = pcall(main)

if not ok then
    printError(tostring(reason))

    if tostring(reason):find("Terminated", 1, true) then
        -- Ctrl+T stops immediately without further movement.
        print("Interrupted. Restore home position before restarting.")
    else
        print("Attempting to return home and unload...")

        local recovered, recoveryError = pcall(function()
            goHome()
            unload()
        end)

        if recovered then
            print("Returned home. Fix the problem, then rerun.")
        else
            printError("Recovery stopped: " .. tostring(recoveryError))
        end
    end

    print(("Relative position: x=%d, z=%d, direction=%d"):format(
        x, z, dir
    ))
end
