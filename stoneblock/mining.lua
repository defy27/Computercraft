-- mining.lua
-- Home layout:
--   Fuel chest: left, at turtle elevation.
--   Output chest: directly above.
--   Field: 15 x 15, extending forward and right.
--
-- Run one pass: mining.lua once
-- Run forever:  mining.lua

local SIZE = 15
local PAUSE_SECONDS = 5
local REQUIRED_FUEL = 252 + 20
local args = { ... }
local RUN_ONCE = args[1] == "once"

-- Relative coordinates:
-- x = blocks right of home
-- z = blocks forward of home
-- dir: 0 forward, 1 right, 2 backward, 3 left
local x, z, dir = 0, 0, 0

local dx = { [0] = 0, 1, 0, -1 }
local dz = { [0] = 1, 0, -1, 0 }

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

    -- Retry briefly for temporary obstructions, such as entities.
    for attempt = 1, 6 do
        local ok
        ok, reason = turtle.forward()

        if ok then
            -- Update coordinates only after a successful move.
            x = x + dx[dir]
            z = z + dz[dir]
            return
        end

        if turtle.detect() then
            break
        end

        sleep(0.5)
    end

    -- Never dig forward: the travel layer should remain clear.
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
    -- Follow already visited cells to the appropriate edge,
    -- then return along the edge and the first column.
    local edge = (x % 2 == 0) and 0 or (SIZE - 1)

    moveTo(x, edge)
    moveTo(0, edge)
    moveTo(0, 0)
    face(0)
end

local function resumeAt(savedX, savedZ, savedDir)
    -- Reverse the route used by goHome().
    local edge = (savedX % 2 == 0) and 0 or (SIZE - 1)

    moveTo(0, edge)
    moveTo(savedX, edge)
    moveTo(savedX, savedZ)
    face(savedDir)
end

local function emptySlot()
    for slot = 1, 16 do
        if turtle.getItemCount(slot) == 0 then
            return slot
        end
    end
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

    for slot = 1, 16 do
        turtle.select(slot)

        -- Repeat because a chest may accept only part of a stack.
        while turtle.getItemCount(slot) > 0 do
            local ok = turtle.dropUp()

            if not ok then
                fail("Output chest is full. Make space, then rerun.")
            end
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

    -- Use any coal already carried before collecting more.
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

    -- Face the fuel chest on the original left side.
    face(3)
    requireChest(turtle.inspect, "on the left of home.")

    local collected = 0

    while not enoughFuel() and collected < 64 do
        local slot = emptySlot()

        if not slot then
            -- We are still at home; unloading works while turned.
            unload()
            slot = emptySlot()
        end

        if not slot then
            fail("No inventory space available for coal.")
        end

        turtle.select(slot)

        local ok, reason = turtle.suck(64 - collected)
        if not ok then
            fail("Cannot collect coal: " .. tostring(reason))
        end

        -- The selected slot was empty and can hold the whole batch.
        local item = turtle.getItemDetail(slot)
        if not item or item.name ~= "minecraft:coal" then
            fail("The fuel chest must contain only coal.")
        end

        collected = collected + item.count

        -- Burn the collected batch into the internal fuel buffer.
        check(turtle.refuel())
    end

    face(0)

    if not enoughFuel() then
        fail("Insufficient fuel after collecting up to 64 coal.")
    end
end

local function mineBelow()
    -- Air and liquids do not need digging.
    if not turtle.detectDown() then
        return
    end

    local slot = emptySlot()

    if not slot then
        local savedX, savedZ, savedDir = x, z, dir

        print("Inventory full; returning to unload.")
        goHome()
        unload()
        ensureFuel()
        resumeAt(savedX, savedZ, savedDir)

        slot = emptySlot()
    end

    if not slot then
        fail("No inventory space after unloading.")
    end

    turtle.select(slot)

    -- Exactly one dig attempt per cell avoids getting stuck
    -- digging an instantly regenerating block forever.
    local ok, reason = turtle.digDown()

    if not ok and turtle.detectDown() then
        fail("Cannot mine below: " .. tostring(reason))
    end
end

local function mineArea()
    for column = 0, SIZE - 1 do
        for position = 1, SIZE do
            mineBelow()

            if position < SIZE then
                forward()
            end
        end

        if column < SIZE - 1 then
            -- Shift one column right, then reverse direction.
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
        unload() -- Also clears any inventory present at startup.

        pass = pass + 1
        print(("Pass %d; fuel: %s"):format(
            pass, tostring(turtle.getFuelLevel())
        ))

        mineArea()
        goHome()
        unload()

        print("Home, facing original direction; unloaded.")

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
            print("Home and unloaded. Fix the problem, then rerun.")
        else
            printError("Recovery stopped: " .. tostring(recoveryError))
        end
    end

    print(("Relative position: x=%d, z=%d, direction=%d"):format(
        x, z, dir
    ))
end
