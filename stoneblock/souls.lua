-- mining.lua
--
-- Each turtle covers two rows of 15 blocks:
--   1. Mine forward along the starting row.
--   2. Move one block right.
--   3. Mine backward along the second row.
--   4. Move left into the starting position.
--   5. Unload above and repeat.
--
-- Home layout:
--   Fuel chest: directly LEFT.
--   Output chest: directly ABOVE.
--
-- The starting position counts as the first mining position.
-- Keep the travel layer clear.
--
-- Run once: mining.lua once
-- Repeat:   mining.lua
--
-- Always start at home in the original direction.
-- Position tracking is not saved across reboots.

local ROW_LENGTH = 15
local PAUSE_SECONDS = 0.5

-- 14 forward + 1 right + 14 backward + 1 left = 30.
local REQUIRED_FUEL = 2 * ROW_LENGTH + 20

local args = { ... }
local RUN_ONCE = args[1] == "once"

-- Relative coordinates:
-- x: right of home
-- z: forward of home
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

    for attempt = 1, 6 do
        local ok
        ok, reason = turtle.forward()

        if ok then
            x = x + dx[dir]
            z = z + dz[dir]
            return
        end

        if turtle.detect() then
            break
        end

        sleep(0.5)
    end

    -- Never dig forward into equipment or another turtle.
    fail("Movement blocked: " .. tostring(reason))
end

local function goHome()
    -- From the second row, move onto the first row.
    -- The first row has already been traversed.
    if x > 0 then
        face(3)

        while x > 0 do
            forward()
        end
    end

    if z > 0 then
        face(2)

        while z > 0 do
            forward()
        end
    end

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

    local savedDir = dir
    face(0)

    local warned = false

    for slot = 1, 16 do
        if turtle.getItemCount(slot) > 0 then
            turtle.select(slot)

            while turtle.getItemCount(slot) > 0 do
                local before = turtle.getItemCount(slot)

                turtle.dropUp()

                if turtle.getItemCount(slot) == before then
                    if not warned then
                        print("Output full; discarding remaining items.")
                        warned = true
                    end

                    turtle.dropDown()

                    if turtle.getItemCount(slot) == before then
                        turtle.drop()
                    end
                end

                -- Continue harvesting even if unloading is blocked.
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
    -- Only used when collecting fuel.
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
        fail("Configured fuel capacity is too low.")
    end

    -- Use any coal already carried first.
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

    -- Keep the same slot selected.
    -- Other slots fill automatically.
    -- Excess items drop into the world when inventory is full.
    local ok, reason = turtle.digDown()

    if not ok and turtle.detectDown() then
        fail("Cannot mine below: " .. tostring(reason))
    end
end

local function mineRows()
    turtle.select(1)

    -- First row: forward.
    face(0)

    for position = 1, ROW_LENGTH do
        mineBelow()

        if position < ROW_LENGTH then
            forward()
        end
    end

    -- Move one block right onto the second row.
    face(1)
    forward()

    -- Second row: backward toward home.
    face(2)

    for position = 1, ROW_LENGTH do
        mineBelow()

        if position < ROW_LENGTH then
            forward()
        end
    end

    -- Now at x=1, z=0.
    -- goHome() moves left and restores the original direction.
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

        mineRows()
        goHome()
        unload()

        print("Home; pass complete.")

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
        -- Respect Ctrl+T as an immediate stop.
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
