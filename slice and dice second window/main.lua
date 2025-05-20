-- second_window.lua
--    "C:\Program Files\LOVE\love.exe" "C:\slice and dice second window"
local status = { player = {}, log = {} }

function love.load()
    love.window.setTitle("Battle Log & Stats")
    love.window.setMode(400, 600)
end

local json = require("dkjson")

function love.update(dt)
    local f = io.open("C:\\Game2\\status.json", "r")
    if f then
        local content = f:read("*a")
        f:close()
        local decoded, pos, err = json.decode(content)
        if decoded then
            status = decoded
        else
            print("JSON decode error:", err)
            status = { player = {}, log = {} }
        end
    else
        status = { player = {}, log = {} }
    end
end

function love.draw()
    local y = 10
    love.graphics.setFont(love.graphics.newFont(14))
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("== Player Stats ==", 10, y)
    y = y + 20
    love.graphics.print("HP: " .. (status.player.hp or "?") .. "/" .. (status.player.maxHP or "?"), 10, y)
    y = y + 20
    love.graphics.print("Block: " .. (status.player.block or "?"), 10, y)
    y = y + 20

    if status.player.isStunned and status.player.isStunned > 0 then
        love.graphics.setColor(1, 1, 0)
        love.graphics.print("STUNNED: " .. status.player.isStunned .. " turns", 10, y)
        y = y + 20
        love.graphics.setColor(1, 1, 1)
    end

    y = y + 10
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("== Battle Log ==", 10, y)
    y = y + 20

    local logs = status.log or {}
    for i = math.max(1, #logs - 10), #logs do
        local line = logs[i] or ""
        local color = {1, 1, 1}
        local prefix = ""

        if line:find("deals") then
            color = {1, 0.3, 0.3}
            prefix = "⚔️ "
        elseif line:find("heals") then
            color = {0.3, 1, 0.3}
            prefix = "💚 "
        elseif line:find("stunned") or line:find("stuns") then
            color = {1, 1, 0.2}
            prefix = "💢 "
        elseif line:find("block") then
            color = {0.5, 0.8, 1}
            prefix = "🛡️ "
        end

        love.graphics.setColor(color)
        love.graphics.print(prefix .. line, 10, y)
        y = y + 16
    end

    love.graphics.setColor(1, 1, 1)
end


