--    "C:\Program Files\LOVE\love.exe" "C:\slice and dice"  

love.graphics.setDefaultFilter("nearest", "nearest")
math.randomseed(os.time())

-- ==============
-- ASSETS & VARS
-- ==============

local json = require("json")
local font, smallFont
local heroImage, enemyImage, backgroundImage
local healSound, hitSound, rollSound

local soundVolume = 0.6

function loadAssets()
    font = love.graphics.newFont("assets/fonts/pressstart2p.ttf", 16)
    smallFont = love.graphics.newFont(12)

    heroImage = love.graphics.newImage("assets/images/hero.png")
    enemyImage = love.graphics.newImage("assets/images/enemy.png")
    backgroundImage = love.graphics.newImage("assets/images/background.png")

    healSound = love.audio.newSource("assets/sounds/heal.wav", "static")
    hitSound = love.audio.newSource("assets/sounds/hit.wav", "static")
    rollSound = love.audio.newSource("assets/sounds/roll.wav", "static")

    healSound:setVolume(soundVolume)
    hitSound:setVolume(soundVolume)
    rollSound:setVolume(soundVolume)
end

-- ============
-- GAME STATE
-- ============

local gameState = "menu" -- menu, battle, gameover
local battleLog = {}
local currentTurn = "player"
local lockedDice = {}
local cooldowns = {}
local cooldownTurns = 3
local message = ""


-- For animations and effects
local flashTimer = 0
local flashColor = {1,1,1,0} -- alpha 0 means no flash
local enemyShakeTimer = 0
local diceRolling = false
local diceRollTimers = {}

-- ============
-- ENTITIES
-- ============

local Player = {
    name = "Shrek",
    maxHP = 20,
    hp = 20,
    dice = {
        {type="hit", value=math.random(1,3)}, {type="hit", value=math.random(1,3)}, {type="block", value=math.random(1,3)},
        {type="heal", value=math.random(1,3)}, {type="hit", value=math.random(1,3)}, {type="heal", value=math.random(1,3)}
    },
    x = 100, y = 200,
    color = {0.2, 0.7, 1},
    block = 0
}

local Enemy = {
    name = "Enemy",
    maxHP = 15,
    hp = 15,
    block = 0,
    attackMoves = {
        {type="hit", value=2}, {type="hit", value=3}, {type="hit", value=1},
        {type="block", value=1}, {type="block", value=2},
        {type="heal", value=1}, {type="heal", value=2}
    },
    x = 400, y = 200,
    color = {1, 0.3, 0.3},
}

-- ===============
-- PARTICLES
-- ===============

local particles = {}

function spawnParticles(x, y, color)
    for i = 1, 15 do
        table.insert(particles, {
            x = x, y = y,
            dx = love.math.random(-20, 20),
            dy = love.math.random(-20, 20),
            alpha = 1,
            color = color
        })
    end
end

function updateParticles(dt)
    for i = #particles, 1, -1 do
        local p = particles[i]
        p.x = p.x + p.dx * dt
        p.y = p.y + p.dy * dt
        p.alpha = p.alpha - dt
        if p.alpha <= 0 then
            table.remove(particles, i)
        end
    end
end

function drawParticles()
    for _, p in ipairs(particles) do
        love.graphics.setColor(p.color[1], p.color[2], p.color[3], p.alpha)
        love.graphics.circle("fill", p.x, p.y, 4)
    end
    love.graphics.setColor(1, 1, 1)
end

-- ==================
-- DRAW HELPERS
-- ==================

function drawHealthBar(unit, x, y, width, height)
    local percent = unit.hp / unit.maxHP
    love.graphics.setColor(0.2, 0.2, 0.2)
    love.graphics.rectangle("fill", x, y, width, height)
    love.graphics.setColor(1 - percent, percent, 0)
    love.graphics.rectangle("fill", x, y, width * percent, height)
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("line", x, y, width, height)
    love.graphics.printf(unit.name .. ": " .. unit.hp .. "/" .. unit.maxHP, x, y - 18, width, "center")
end

function drawDice(dice, locked)
    for i, die in ipairs(dice) do
        local x = 100 + (i - 1) * 70
        local y = 400
        love.graphics.setColor(0.1, 0.1, 0.1)
        love.graphics.rectangle("fill", x - 4, y - 4, 72, 72, 8)

        -- Determine color
        local color
        if cooldowns[i] and cooldowns[i] > 0 then
            color = {0.4, 0.4, 0.4} -- greyed out for cooldown
        elseif locked[i] then
            color = {0.8, 0.3, 0.3} -- red-ish for locked
        else
            color = {0.8, 0.8, 0.8} -- normal
        end
        love.graphics.setColor(color)
        love.graphics.rectangle("fill", x, y, 64, 64, 8)

        -- Draw text
        love.graphics.setColor(0, 0, 0)
        local text = die.type:upper() .. "\n" .. die.value
        if cooldowns[i] and cooldowns[i] > 0 then
            text = text .. "\nCD: " .. cooldowns[i]
        end
        love.graphics.setFont(smallFont)
        love.graphics.printf(text, x, y + 6, 64, "center")
    end
    love.graphics.setColor(1, 1, 1)
end

function drawBattleLog()
    local logX = 10
    local logY = 280
    local logWidth = 300
    local logHeight = 100

    -- Background
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", logX, logY, logWidth, logHeight, 8)

    -- Title
    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(mediumFont)
    love.graphics.printf("📜 Battle Log", logX, logY + 4, logWidth, "center")

    -- Log lines
    love.graphics.setFont(smallFont)
    for i = 1, math.min(5, #battleLog) do
        local line = battleLog[#battleLog - i + 1]

        -- Optional: parse type from string prefix or keywords
        local color = {1, 1, 1}
        local prefix = ""
        if line:find("deals") then
            color = {1, 0.3, 0.3} -- red for damage
            prefix = "⚔️ "
        elseif line:find("heals") then
            color = {0.3, 1, 0.3} -- green for healing
            prefix = "💚 "
        elseif line:find("stunned") or line:find("stuns") then
            color = {1, 1, 0.2} -- yellow for stun
            prefix = "💢 "
        elseif line:find("block") then
            color = {0.5, 0.8, 1} -- blue for block
            prefix = "🛡️ "
        end

        -- Timestamp
        local timeStr = os.date("[%H:%M:%S]")

        -- Draw line
        love.graphics.setColor(color)
        local fullLine = string.format("%s %s%s", timeStr, prefix, line)
        love.graphics.printf(fullLine, logX + 6, logY + 20 + (i - 1) * 16, logWidth - 12, "left")
    end

    love.graphics.setColor(1, 1, 1) -- Reset
end

function log(msg)
    table.insert(battleLog, msg)
    if #battleLog > 20 then
        table.remove(battleLog, 1)
    end
end

-- ==============
-- DRAW SCREENS
-- ==============

function drawMenu()
    love.graphics.setFont(font)
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("Slice & Dice", 0, 100, love.graphics.getWidth(), "center")
    love.graphics.printf("Press [Enter] to Start", 0, 150, love.graphics.getWidth(), "center")
    love.graphics.printf("Press [ESC] to Quit", 0, 180, love.graphics.getWidth(), "center")
end

function drawGameOver()
    love.graphics.setFont(font)
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("GAME OVER", 0, 180, love.graphics.getWidth(), "center")
    love.graphics.printf("Press [R] to Restart", 0, 220, love.graphics.getWidth(), "center")
    love.graphics.printf("Press [ESC] to Quit", 0, 260, love.graphics.getWidth(), "center")
end

function drawBattle()
    love.graphics.setFont(font)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(currentTurn == "player" and "Your Turn" or "Enemy Turn", 20, 20)

    -- Enemy shake effect
    local shakeX, shakeY = 0, 0
    if enemyShakeTimer > 0 then
        shakeX = love.math.random(-4,4)
        shakeY = love.math.random(-4,4)
        
    end

    love.graphics.draw(heroImage, Player.x, Player.y)
    love.graphics.draw(enemyImage, Enemy.x + shakeX, Enemy.y + shakeY)

    drawHealthBar(Player, Player.x, Player.y - 20, 100, 15)
    drawHealthBar(Enemy, Enemy.x, Enemy.y - 20, 100, 15)

    drawDice(Player.dice, lockedDice)
    drawBattleLog()
    drawParticles()

    -- Flash effect for damage/heal
    if flashTimer > 0 then
        love.graphics.setColor(flashColor)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
    end
    love.graphics.setColor(1, 1, 1)
end

function saveGame()
    local data = {
        player = {
            hp = Player.hp,
            maxHP = Player.maxHP,
            block = Player.block,
            isStunned = (playerStunTurns or 0) > 0 and playerStunTurns or 0
        },
        enemy = {
            name = Enemy.name,
            hp = Enemy.hp,
            maxHP = Enemy.maxHP,
            block = Enemy.block,
            -- add other fields you want to save, e.g., attackMoves or color if needed
        },
        log = battleLog
    }

    local encoded = json.encode(data, { indent = true })
    local f = io.open("save.json", "w")
    if f then
        f:write(encoded)
        f:close()
    end
end

function loadGame()
    local f = io.open("save.json", "r")
    if f then
        local content = f:read("*a")
        f:close()
        local data = json.decode(content)

        if data then
            Player.hp = data.player.hp
            Player.maxHP = data.player.maxHP
            Player.block = data.player.block
            playerStunTurns = data.player.isStunned or 0

            battleLog = data.log or {}

            Enemy.hp = data.enemy.hp
            Enemy.maxHP = data.enemy.maxHP
            Enemy.block = data.enemy.block
            -- if you saved other fields, assign here too
        end
    end
end

-- ==============
-- GAME LOOP
-- ==============

function love.load()
    love.window.setTitle("Slice&Dice")
    love.graphics.setDefaultFilter("nearest", "nearest")
    math.randomseed(os.time())

    mediumFont = love.graphics.newFont("assets/fonts/pressstart2p.ttf", 16)
    smallFont = love.graphics.newFont("assets/fonts/pressstart2p.ttf", 12)
    font = love.graphics.newFont("assets/fonts/pressstart2p.ttf", 24)

    loadAssets()
    restartGame()
end

local turnDelayTimer = 0

function love.update(dt)
    updateParticles(dt)
    writeStatusFile()

    if flashTimer > 0 then
        flashTimer = flashTimer - dt
        if flashTimer < 0 then flashTimer = 0 end
    end

    if enemyShakeTimer > 0 then
        enemyShakeTimer = enemyShakeTimer - dt
        if enemyShakeTimer < 0 then enemyShakeTimer = 0 end
    end

    if diceRolling then
        local allDone = true
        for i, timer in pairs(diceRollTimers) do
            diceRollTimers[i] = timer - dt
            if diceRollTimers[i] <= 0 then
                diceRollTimers[i] = nil
            else
                -- flicker value for dice rolling animation
                Player.dice[i].value = love.math.random(1, 3)
                allDone = false
            end
        end
        if allDone then
            diceRolling = false
        end
    end

    if gameState == "battle" then
        if currentTurn == "enemy" then
            turnDelayTimer = turnDelayTimer + dt
            if turnDelayTimer > 1.5 then
                enemyAction()
                turnDelayTimer = 0
            end
        end
    end
end

function love.draw()
    love.graphics.draw(backgroundImage, 0, 0)
    if gameState == "menu" then
        drawMenu()
    elseif gameState == "battle" then
        drawBattle()
    elseif gameState == "gameover" then
        drawGameOver()
    end
end

-- ==============
-- INPUT
-- ==============

function love.keypressed(key)
    -- Global hotkeys (save/load) work in any state
    if key == "f5" then
        saveGame()
        table.insert(battleLog, "Game saved.")
        return
    elseif key == "f9" then
        loadGame()
        table.insert(battleLog, "Game loaded.")
        return
    end

    -- Game state-specific key handling
    if gameState == "menu" then
        if key == "return" then
            gameState = "battle"
        elseif key == "escape" then
            love.event.quit()
        end

    elseif gameState == "battle" then
        if currentTurn == "player" then
            -- Prevent input if player is stunned
            if Player.isStunned and Player.isStunned > 0 then
                return
            end

            if key == "r" then
                rollDice()
            elseif tonumber(key) and tonumber(key) >= 1 and tonumber(key) <= #Player.dice then
                toggleLockDice(tonumber(key))
            elseif key == "space" then
                playerAction()
            elseif key == "escape" then
                love.event.quit()
            end
        end

    elseif gameState == "gameover" then
        if key == "r" then
            restartGame()
            gameState = "battle"
        elseif key == "escape" then
            love.event.quit()
        end
    end
end

function toggleLockDice(index)
    if cooldowns[index] and cooldowns[index] > 0 then return end

    if lockedDice[index] then
        -- Unlock the die if already locked
        lockedDice[index] = false
    else
        -- Unlock all dice, then lock the chosen one
        for i = 1, #Player.dice do
            lockedDice[i] = false
        end
        lockedDice[index] = true
    end
end

function rollDice()
    if diceRolling then return end
    diceRolling = true
    diceRollTimers = {}
    for i = 1, #Player.dice do
        if not lockedDice[i] and (not cooldowns[i] or cooldowns[i] <= 0) then
            -- Start a dice roll timer between 0.3 and 0.6 seconds
            diceRollTimers[i] = love.math.random() * 0.3 + 0.3 
        end
    end
    rollSound:play()
end

function playerAction()
    if diceRolling then return end -- wait for rolling to finish
    
    local chosenIndex = nil
    for i = 1, #lockedDice do
        if lockedDice[i] then
            chosenIndex = i
            break
        end
    end
    if not chosenIndex then
        log("Lock a die before acting!")
        return
    end

    local die = Player.dice[chosenIndex]

    if die.type == "hit" then
        local damage = die.value
        -- Calculate damage considering enemy block
        local actualDamage = math.max(0, damage - Enemy.block)
        Enemy.block = math.max(0, Enemy.block - damage)
        Enemy.hp = math.max(0, Enemy.hp - actualDamage)
        log("You hit the enemy for " .. actualDamage .. " damage!")
        hitSound:play()
        spawnParticles(Enemy.x + 50, Enemy.y + 50, {1, 0, 0})
        enemyShakeTimer = 0.5
        flashColor = {1, 0, 0, 0.4}
        flashTimer = 0.3
    elseif die.type == "heal" then
        Player.hp = math.min(Player.maxHP, Player.hp + die.value)
        log("You heal for " .. die.value .. " HP!")
        healSound:play()
        spawnParticles(Player.x + 50, Player.y + 50, {0, 1, 0})
        flashColor = {0, 1, 0, 0.4}
        flashTimer = 0.3
    elseif die.type == "block" then
        Player.block = Player.block + die.value
        log("You gain " .. die.value .. " block!")
        spawnParticles(Player.x + 50, Player.y + 50, {0, 0, 1})
        flashColor = {0, 0, 1, 0.4}
        flashTimer = 0.3
    end

    cooldowns[chosenIndex] = cooldownTurns
    lockedDice[chosenIndex] = false

    -- Advance turn
    currentTurn = "enemy"

    -- Reduce cooldowns on all dice by 1 for next turn
    for i = 1, #cooldowns do
        if cooldowns[i] and cooldowns[i] > 0 then
            cooldowns[i] = cooldowns[i] - 1
            if cooldowns[i] < 0 then cooldowns[i] = 0 end
        end
    end
end

local playerStunTurns = 0
local enemyHasStunned = false  -- stun usage tracker

function enemyAction()
    if Enemy.hp <= 6 and playerStunTurns == 0 and not enemyHasStunned then
        log("Enemy uses a special stun attack!")
        playerStunTurns = 3
        enemyHasStunned = true
        flashColor = {1, 1, 0, 0.5} -- yellow flash
        flashTimer = 0.5
        enemyShakeTimer = 1
    else
        -- Select enemy move
        local move = nil
        if playerStunTurns > 0 then
            -- Player stunned: filter to only damaging moves
            local damagingMoves = {}
            for _, m in ipairs(Enemy.attackMoves) do
                if m.type == "hit" then
                    table.insert(damagingMoves, m)
                end
            end
            move = damagingMoves[love.math.random(#damagingMoves)]
        else
            -- Player not stunned: pick any move
            move = Enemy.attackMoves[love.math.random(#Enemy.attackMoves)]
        end

        -- Execute move
        if move.type == "hit" then
            local damage = move.value
            local actualDamage = math.max(0, damage - Player.block)
            Player.block = math.max(0, Player.block - damage)
            Player.hp = math.max(0, Player.hp - actualDamage)
            log("Enemy hits you for " .. actualDamage .. " damage!")
            hitSound:play()
            spawnParticles(Player.x + 50, Player.y + 50, {1, 0, 0})
            enemyShakeTimer = 0.5
            flashColor = {1, 0, 0, 0.4}
            flashTimer = 0.3
        elseif move.type == "heal" then
            Enemy.hp = math.min(Enemy.maxHP, Enemy.hp + move.value)
            log("Enemy heals for " .. move.value .. " HP!")
            healSound:play()
            spawnParticles(Enemy.x + 50, Enemy.y + 50, {0, 1, 0})
            flashColor = {0, 1, 0, 0.4}
            flashTimer = 0.3
        elseif move.type == "block" then
            Enemy.block = Enemy.block + move.value
            log("Enemy gains " .. move.value .. " block!")
            spawnParticles(Enemy.x + 50, Enemy.y + 50, {0, 0, 1})
            flashColor = {0, 0, 1, 0.4}
            flashTimer = 0.3
        end
    end

    -- End enemy turn, start player turn if not stunned
    if playerStunTurns > 0 then
        playerStunTurns = playerStunTurns - 1
        log("You are stunned! Turns left: " .. playerStunTurns)
        if playerStunTurns == 0 then
            log("You are no longer stunned!")
        end
    else
        currentTurn = "player"
    end

    -- Check for game over
    if Player.hp <= 0 then
        gameState = "gameover"
        log("You were defeated!")
    elseif Enemy.hp <= 0 then
        gameState = "gameover"
        log("You defeated the enemy!")
    end
end

local json = require("json")

function writeStatusFile()
    local data = {
        player = {
            hp = Player.hp,
            maxHP = Player.maxHP,
            block = Player.block,
            isStunned = playerStunTurns > 0 and playerStunTurns or 0
        },
        log = {}
    }

    -- Keep the last 20 log entries
    for i = math.max(1, #battleLog - 19), #battleLog do
        table.insert(data.log, battleLog[i])
    end

    local encoded = json.encode(data, { indent = true })

    local f = io.open("C:\\Game2\\status.json", "w")
    if f then
        f:write(encoded)
        f:close()
    end
end

function restartGame()
    -- Reset all game variables and entities
    Player.hp = Player.maxHP
    Player.block = 0
    Enemy.hp = Enemy.maxHP
    Enemy.block = 0
    cooldowns = {}
    lockedDice = {}
    battleLog = {}
    currentTurn = "player"
    message = ""
    flashTimer = 0
    enemyShakeTimer = 0
    diceRolling = false
    diceRollTimers = {}
end
