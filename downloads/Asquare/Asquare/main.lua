-- ============================================================================
--  Asquare Ultra：本地 + 局域网联机 超级合并版（含子弹破墙技能 + 语法修复）
--  依赖：LuaSocket（LOVE 自带）
-- ============================================================================
local socket = require("socket")
-- ============================================================================
--  基础常量
-- ============================================================================
GRID                  = 32
ZOMBIE_MOVE_INTERVAL  = 1.2
BULLET_SPEED          = 12
MAX_HP                = 10
UDP_PORT              = 50001
TCP_PORT              = 50002
BROADCAST_IP          = "255.255.255.255"
-- ============================================================================
--  游戏世界
-- ============================================================================
players   = {
{ x = 0, y = 0, dirx = 1, diry = 0, hp = MAX_HP, color = {0.3, 1, 0.3}, controls = {}, powerups = {} },
{ x = 0, y = 0, dirx = -1, diry = 0, hp = MAX_HP, color = {1, 1, 0.2}, controls = {}, powerups = {} }
}
zombies   = {}
bullets   = {}
walls     = {}
towerWalls = {}
core       = {x = 0, y = 0}
blocks    = 8
score     = 0
gameTimer = 0
spawnTimer     = 0
spawnInterval  = 2.5
-- ============================================================================
--  游戏状态
-- ============================================================================
gameState ="start"
gameMode  = "1P"
currentMenuSelection     = 1
currentPlaySelection     = 1
currentSettingSelection  = 1
waitingForKey = false
keyToRebind   = nil
musicEnabled  = true
-- ============================================================================
--  强化道具系统
-- ============================================================================
POWERUP_TYPES = {
{
id = "speed",
name = "Speed Boost",
desc = "Move faster",
color = {0.3, 0.8, 1},
apply = function(player) player.powerups.speed = (player.powerups.speed or 0) + 1 end
},
{
id = "damage",
name = "Power Shot",
desc = "+1 bullet damage",
color = {1, 0.3, 0.3},
apply = function(player) player.powerups.damage = (player.powerups.damage or 0) + 1 end
},
{
id = "build",
name = "Builder",
desc = "+3 blocks per kill",
color = {0.3, 1, 0.3},
apply = function(player) player.powerups.build = (player.powerups.build or 0) + 1 end
},
{
id = "multishot",
name = "Multi Shot",
desc = "Shoot 3 bullets",
color = {1, 0.8, 0.2},
apply = function(player) player.powerups.multishot = (player.powerups.multishot or 0) + 1 end
},
{
id = "pierce",
name = "Piercing",
desc = "Bullets pierce zombies",
color = {0.8, 0.3, 1},
apply = function(player) player.powerups.pierce = (player.powerups.pierce or 0) + 1 end
},
{
id = "wallbreak",
name = "Wall Breaker",
desc = "Bullets destroy walls",
color = {0.7, 0.7, 0.7},
apply = function(player) player.powerups.wallbreak = (player.powerups.wallbreak or 0) + 1 end
},
{
id = "regen",
name = "Regeneration",
desc = "Slow HP regen",
color = {1, 0.5, 0.8},
apply = function(player) player.powerups.regen = (player.powerups.regen or 0) + 1 end
}
}
powerupSelection = {
active = false,
options = {},
selectedIndex  = 1,
milestone = 0
}
-- ============================================================================
--  网络模块
-- ============================================================================
net = {
role        = nil,
roomName    = "",
udpBcast    = nil,
udpGame     = nil,
tcp         = nil,
peer        = nil,
lastBeat    = 0,
remoteInput = {},
roomConflict= false
}
-- ============================================================================
--  音频引擎
-- ============================================================================
local synth = {}
function synth.generate(f1, f2, duration, wave, volume, curve)
local sampleRate = 44100
local length = math.floor(sampleRate * duration)
local data = love.sound.newSoundData(length, sampleRate, 16, 1)
curve = curve or 4
for i = 0, length - 1 do
local t = i / sampleRate
local progress = i / (length - 1)
local freq = f1 + (f2 - f1) * progress
local val = 0
if wave == "sine" then
val = math.sin(2 * math.pi * freq * t)
elseif wave == "square" then
val = math.sin(2 * math.pi * freq * t) > 0 and 0.15 or -0.15
elseif wave == "noise" then
val = math.random() * 2 - 1
end
local envelope = math.exp(-curve * progress) * (1 - progress)
data:setSample(i, val * envelope * (volume or 0.5))
end
return love.audio.newSource(data)
end
-- ============================================================================
--  音效表
-- ============================================================================
SFX = {}
function initSFX()
SFX.menu_select = synth.generate(880, 1760, 0.05,  "sine", 0.1, 8)
SFX.start_game  = synth.generate(440, 880, 0.4,  "sine", 0.3, 2)
SFX.shoot       = synth.generate(1200, 400, 0.08,  "sine", 0.1, 6)
SFX.build       = synth.generate(220, 880, 0.15,  "sine", 0.2, 4)
SFX.hit         = synth.generate(600, 300, 0.35,  "sine", 0.25, 8)
SFX.kill        = synth.generate(1000, 2000, 0.08,  "sine", 0.2, 5)
SFX.score       = synth.generate(523, 1046, 0.6,  "sine", 0.3, 1.5)
SFX.gameover    = synth.generate(200, 50, 1.5,  "square", 0.3, 2)
SFX.powerup     = synth.generate(660, 1320, 0.3,  "sine", 0.3, 3)
SFX.wallbreak   = synth.generate(150, 50, 0.15, "square", 0.2, 10)
end
-- ============================================================================
--  键位配置
-- ============================================================================
keyConfig =  {
p1 = { up =  "w", down =  "s", left =  "a", right =  "d", shoot =  "space", build =  "m" },
p2 = { up =  "up", down =  "down", left =  "left", right =  "right", shoot =  "return", build =  "rshift" }
}
local keyDisplayNames = {
[ "up"] =  "Up", [ "down"] =  "Down", [ "left"] =  "Left", [ "right"] =  "Right",
[ "return"] =  "Enter", [ "space"] =  "Space", [ "rshift"] =  "R-Shift",
[ "lshift"] =  "L-Shift", [ "tab"] =  "Tab", [ "escape"] =  "Esc"
}
local function niceKeyName(key) return keyDisplayNames[key] or string.upper(key) end
-- ============================================================================
--  工具函数
-- ============================================================================
function inMap(x, y) return x >= 0 and x < MAP_W and y >= 0 and y < MAP_H end
function wallAt(x, y)
for _, w in ipairs(walls) do if w.x == x and w.y == y then return w end end
end
function towerWallAt(x, y)
for _, tw in ipairs(towerWalls) do if tw.x == x and tw.y == y then return tw end end
end
function zombieAt(x, y)
for _, z in ipairs(zombies) do if z.x == x and z.y == y then return z end end
end
function findFreeCellFromDir(x, y, dx, dy)
local dirs = {{dx, dy}, {dy, -dx}, {-dx, -dy}, {-dy, dx}}
for _, d in ipairs(dirs) do
local nx, ny = x + d[1], y + d[2]
if inMap(nx, ny) and not wallAt(nx, ny) and not towerWallAt(nx, ny) and not (nx == core.x and ny == core.y) and not zombieAt(nx, ny) then return nx, ny end
end
end
function floodFill(sx, sy)
visited = {}
for y = 0, MAP_H - 1 do
visited[y] = {}
for x = 0, MAP_W - 1 do visited[y][x] = false end
end
local queue = {{sx, sy}}
if inMap(sx, sy) then visited[sy][sx] = true end
local dirs = {{0,1},{1,0},{0,-1},{-1,0}}
while #queue > 0 do
local cur = table.remove(queue, 1)
for _, d in ipairs(dirs) do
local nx, ny = cur[1] + d[1], cur[2] + d[2]
if inMap(nx, ny) and not visited[ny][nx] and not wallAt(nx, ny) and not towerWallAt(nx, ny) then
visited[ny][nx] = true; table.insert(queue, {nx, ny})
end
end
end
end
function killZombiesInClosedAreas()
if #walls == 0 then return end
floodFill(0, 0)
local killedCount = 0
for i = #zombies, 1, -1 do
local z = zombies[i]
if not visited[z.y][z.x] then
score = score + z.score
table.remove(zombies, i)
killedCount = killedCount + 1
end
end
if killedCount > 0 then
SFX.score:stop(); SFX.score:play()
checkPowerupMilestone()
end
end
function checkGameOver()
local alive = 0
for i, pl in ipairs(players) do
if gameMode == "1P" and i == 2 then break end
if pl.hp > 0 then alive = alive + 1 end
end
if alive == 0 then
gameState = "gameover"; if bgm then bgm:stop() end; SFX.gameover:play()
end
end
-- ============================================================================
--  随机地图生成
-- ============================================================================
function generateRandomMap()
walls = {}
towerWalls = {}
local numObstacles = math.floor((MAP_W * MAP_H) * 0.03)
for i = 1, numObstacles do
    local x = math.random(2, MAP_W - 3)
    local y = math.random(2, MAP_H - 3)
    local distToCore = math.abs(x - core.x) + math.abs(y - core.y)
    if distToCore > 3 and not wallAt(x, y) then
        table.insert(walls, {x = x, y = y, hp = 5})
    end
end

local crossOffsets = {{0, -1}, {0, 1}, {-1, 0}, {1, 0}}
for _, off in ipairs(crossOffsets) do
    local tx = core.x + off[1]
    local ty = core.y + off[2]
    if inMap(tx, ty) then
        table.insert(towerWalls, {x = tx, y = ty, hp = 5})
    end
end
end
-- ============================================================================
--  强化道具系统函数
-- ============================================================================
function checkPowerupMilestone()
local milestone = math.floor(score / 200) * 200
if milestone > powerupSelection.milestone and milestone > 0 then
powerupSelection.milestone = milestone
showPowerupSelection()
end
end
function showPowerupSelection()
powerupSelection.active = true
powerupSelection.selectedIndex = 1
gameState = "powerup_select"
powerupSelection.options = {}
local available = {}
for i, p in ipairs(POWERUP_TYPES) do table.insert(available, i) end
for i = #available, 2, -1 do
    local j = math.random(i)
    available[i], available[j] = available[j], available[i]
end
for i = 1, math.min(3, #available) do
    table.insert(powerupSelection.options, POWERUP_TYPES[available[i]])
end
SFX.powerup:play()
end
function applySelectedPowerup()
local selected = powerupSelection.options[powerupSelection.selectedIndex]
if selected then
for i, pl in ipairs(players) do
if gameMode == "1P" and i == 2 then break end
if pl.hp > 0 then selected.apply(pl) end
end
end
powerupSelection.active = false
gameState = "playing"
end
function clearPlayerPowerups()
for _, pl in ipairs(players) do pl.powerups = {} end
powerupSelection.milestone = 0
powerupSelection.active = false
end
-- ============================================================================
--  僵尸生成
-- ============================================================================
ZOMBIE_TYPES = {
{hp=1,  score=1,  color={1,0,0},    blocks=1},
{hp=3,  score=3,  color={0.6,0,0.6}, blocks=2},
{hp=6,  score=6,  color={1,0.6,0},   blocks=3},
{hp=10, score=10, color={0,1,1},     blocks=5}
}
function spawnZombie()
local t = ZOMBIE_TYPES[math.random(#ZOMBIE_TYPES)]
local side = ({'t','b','l','r'})[math.random(4)]
local x, y
if side=='t' then x,y = math.random(MAP_W)-1, 0 end
if side=='b' then x,y = math.random(MAP_W)-1, MAP_H-1 end
if side=='l' then x,y = 0, math.random(MAP_H)-1 end
if side=='r' then x,y = MAP_W-1, math.random(MAP_H)-1 end
table.insert(zombies,{x=x, y=y, hp=t.hp, score=t.score, color=t.color, blocks=t.blocks, moveTimer=ZOMBIE_MOVE_INTERVAL})
end
-- ============================================================================
--  网络实现
-- ============================================================================
function netInit()
net.udpBcast = socket.udp(); net.udpBcast:settimeout(0)
net.udpBcast:setoption("broadcast", true); net.udpBcast:setoption("dontroute", true)
net.udpGame  = socket.udp(); net.udpGame:settimeout(0)
net.tcp      = socket.tcp(); net.tcp:settimeout(0)
net.role, net.roomName, net.peer = nil, "", nil
net.lastBeat, net.remoteInput = 0, {}
end
function netSendUDP(msg) net.udpBcast:sendto(msg, BROADCAST_IP, UDP_PORT) end
function netPollUDP()
while true do
local data, ip, port = net.udpBcast:receivefrom()
if not data then break end
local cmd, room, extra = data:match("^(%w+)|([^|]+)|?(.*)")
if cmd == "QUERY" and net.role == "host" and room == net.roomName then
net.udpBcast:sendto("EXISTS|" .. net.roomName, ip, port)
elseif cmd == "EXISTS" and net.role == "client" and room == net.roomName then
net.roomConflict = true
elseif cmd == "JOIN" and net.role == "host" and room == net.roomName then
local myip = net.udpBcast:getsockname()
net.udpBcast:sendto("ACCEPT|" .. net.roomName .. "|" .. myip .. "|" .. TCP_PORT, ip, port)
elseif cmd == "ACCEPT" and net.role == "client" and room == net.roomName then
local hostip, tcpport = extra:match("([^|]+)|(%d+)")
net.tcp = socket.tcp(); net.tcp:settimeout(0); net.tcp:connect(hostip, tonumber(tcpport))
end
end
end
function netCreateRoom(name)
net.roomName, net.role = name, "host"
net.tcp:bind("*", TCP_PORT); net.tcp:listen(1)
net.roomConflict = false
netSendUDP("QUERY|" .. name)
love.timer.sleep(1); netPollUDP()
if net.roomConflict then net.role = nil; return false, "Room name already exists." end
return true
end
function netJoinRoom(name) net.roomName, net.role = name, "client"; netSendUDP("JOIN|" .. name); return true end
function netCheckConnected()
if net.peer then return true end
if net.role == "host" then
local conn = net.tcp:accept(); if conn then conn:settimeout(0); net.peer = conn; return true end
else
if net.tcp and net.tcp:getpeername() then net.peer = net.tcp; return true end
end
end
function netSend(msg) if net.peer then local ok, err = net.peer:send(msg .. "\n"); if not ok then net.peer = nil end end end
function netRecv() if not net.peer then return nil end local msg, err = net.peer:receive("*l"); if err == "closed" then net.peer = nil end; return msg end
function netUpdate(dt)
netPollUDP()
if net.role and not net.peer and netCheckConnected() and net.role == "client" then players[2].hp = MAX_HP end
net.lastBeat = net.lastBeat + dt
if net.lastBeat > 2 then netSend("BEAT"); net.lastBeat = 0 end
while true do
local ln = netRecv(); if not ln then break end
if ln:sub(1,5) == "INPUT" then
local udlrsh = ln:sub(7,12)
net.remoteInput = { up = udlrsh:sub(1,1) == "1", down = udlrsh:sub(2,2) == "1", left = udlrsh:sub(3,3) == "1",
right = udlrsh:sub(4,4) == "1", shoot = udlrsh:sub(5,5) == "1", build = udlrsh:sub(6,6) == "1" }
end
end
end
function netPackInput()
local me = net.role == "host" and players[1] or players[2]
local c = me.controls
local function b(k) return love.keyboard.isDown(c[k]) and "1" or "0" end
return table.concat({ b("up"), b("down"), b("left"), b("right"), b("shoot"), b("build") })
end
function netSendInput() if net.peer then netSend("INPUT|" .. netPackInput()) end end
-- ============================================================================
--  LOVE 加载
-- ============================================================================
onlineInputBuffer = ""; showOnlineError = nil
function love.load()
math.randomseed(os.time())
initSFX(); netInit()
local sw, sh = love.window.getDesktopDimensions()
love.window.setMode(sw, sh, {fullscreen = false, borderless = true})
local topPadding = 70
MAP_W, MAP_H = math.floor(sw / GRID), math.floor((sh - topPadding) / GRID)
players[1].x, players[1].y = math.floor(MAP_W / 2) - 4, math.floor(MAP_H / 2)
players[2].x, players[2].y = math.floor(MAP_W / 2) + 4, math.floor(MAP_H / 2)
players[1].controls = keyConfig.p1; players[2].controls = keyConfig.p2

core.x = math.floor(MAP_W / 2)
core.y = math.floor(MAP_H / 2)

local baseSize = math.min(sw, sh) / 12
mediumFont = love.graphics.newFont(baseSize * 0.25)
smallFont  = love.graphics.newFont(baseSize * 0.18)
overFont   = love.graphics.newFont(baseSize * 1.0)
asciiFont  = love.graphics.newFont(math.floor(sw / 10))
powerupFont = love.graphics.newFont(baseSize * 0.35)

local function makeBGM(bpm, notes)
    local sRate = 44100; local beatLen = sRate * (60 / bpm)
    local data = love.sound.newSoundData(beatLen * #notes, sRate, 16, 1)
    for i, note in ipairs(notes) do
        for j = 0, beatLen - 1 do
            local t = j / sRate
            local val = math.sin(2 * math.pi * note * t) * math.exp(-4 * t)
            data:setSample((i-1)*beatLen + j, val * 0.1)
        end
    end
    local src = love.audio.newSource(data); src:setLooping(true); return src
end
titleBgm = makeBGM(120, {220, 261, 293, 329})
bgm      = makeBGM(140, {110, 130, 146, 164})
asciiTitle = "Asquare"; titleBgm:play()
end
-- ============================================================================
--  输入
-- ============================================================================
function love.textinput(t)
if gameState == "play_submenu" and currentPlaySelection == 3 then onlineInputBuffer = onlineInputBuffer .. t end
end
function love.keypressed(key, scancode, isrepeat)
local shift = love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
if key == "escape" then
if gameState == "settings" or gameState == "play_submenu" then
gameState = "start"; SFX.menu_select:play(); showOnlineError = nil; onlineInputBuffer = ""
if gameMode == "online" and net.peer then net.peer:close(); net.role = nil; net.peer = nil; net.roomName = "" end
return
elseif gameState == "playing" and gameMode == "online" then
if net.peer then net.peer:close() end; net.role = nil; net.peer = nil; net.roomName = ""
gameState = "start"; titleBgm:play(); if bgm then bgm:stop() end; return
elseif gameState == "playing" then love.event.quit()
elseif gameState == "powerup_select" then return
else love.event.quit() end
end
if gameState == "powerup_select" then
    if key == "tab" then
        powerupSelection.selectedIndex = powerupSelection.selectedIndex + (shift and -1 or 1)
        if powerupSelection.selectedIndex < 1 then powerupSelection.selectedIndex = #powerupSelection.options end
        if powerupSelection.selectedIndex > #powerupSelection.options then powerupSelection.selectedIndex = 1 end
        SFX.menu_select:play()
    elseif key == "return" then
        applySelectedPowerup()
        SFX.start_game:play()
    end
    return
end

if gameState == "start" then
    if key == "tab" then
        currentMenuSelection = currentMenuSelection + (shift and -1 or 1)
        if currentMenuSelection < 1 then currentMenuSelection = 3 end; if currentMenuSelection > 3 then currentMenuSelection = 1 end
        SFX.menu_select:play()
    elseif key == "return" or key == "space" then
        if currentMenuSelection == 1 then gameState = "play_submenu"; currentPlaySelection = 1; SFX.menu_select:play()
        elseif currentMenuSelection == 2 then gameState = "settings"; currentSettingSelection = 1; SFX.menu_select:play()
        elseif currentMenuSelection == 3 then love.event.quit() end
    end
    return
end

if gameState == "play_submenu" then
    if key == "tab" then
        currentPlaySelection = currentPlaySelection + (shift and -1 or 1)
        if currentPlaySelection < 1 then currentPlaySelection = 3 end; if currentPlaySelection > 3 then currentPlaySelection = 1 end
        SFX.menu_select:play()
    elseif key == "return" or key == "space" then
        if currentPlaySelection == 1 then gameMode = "1P"; startLocalGame()
        elseif currentPlaySelection == 2 then gameMode = "2P"; startLocalGame()
        elseif currentPlaySelection == 3 then
            if onlineInputBuffer == "" then showOnlineError = "Room name is required."; return end
            local ok, err = netCreateRoom(onlineInputBuffer); if not ok then showOnlineError = err; return end
            gameMode = "online"; titleBgm:stop(); SFX.start_game:play(); gameState = "playing"
            if musicEnabled then bgm:play() end; players[2].hp = 0
        end
    elseif key == "backspace" and currentPlaySelection == 3 then onlineInputBuffer = onlineInputBuffer:sub(1, -2) end
    return
end

if gameState == "settings" then
    if waitingForKey then
        if key ~= "escape" then
            local keys = { "up", "down", "left", "right", "shoot", "build" }
            local target = keyToRebind <= 7 and keyConfig.p1 or keyConfig.p2
            local idx = keyToRebind <= 7 and (keyToRebind - 1) or (keyToRebind - 7)
            target[keys[idx]] = key; waitingForKey = false; keyToRebind = nil; SFX.menu_select:play()
        end; return
    end
      if key == "tab" then
        currentSettingSelection = currentSettingSelection + (shift and -1 or 1)
        if currentSettingSelection < 1 then currentSettingSelection = 13 end; if currentSettingSelection > 13 then currentSettingSelection = 1 end
        SFX.menu_select:play()
    elseif key == "return" or key == "space" then
        if currentSettingSelection == 1 then
            musicEnabled = not musicEnabled
            if musicEnabled then titleBgm:play(); if gameState == "playing" then bgm:play() end
            else titleBgm:stop(); bgm:stop() end
            SFX.menu_select:play()
        else
            waitingForKey = true; keyToRebind = currentSettingSelection; SFX.menu_select:play()
        end
    end
    return
end

if gameState == "playing" then
    if gameMode ~= "online" then
        for i, pl in ipairs(players) do
            if gameMode == "1P" and i == 2 then break end; if pl.hp <= 0 then goto continue end
            local c = pl.controls
            local moveSpeed = 1 + (pl.powerups.speed or 0)
            
            if key == c.up then 
                 for s = 1, moveSpeed do
                    local newY = pl.y - 1
                    if inMap(pl.x, newY) then pl.y = newY end
                end
                 pl.dirx, pl.diry = 0, -1 
            end
            if key == c.down then 
                for s = 1, moveSpeed do
                     local newY = pl.y + 1
                     if inMap(pl.x, newY) then pl.y = newY end
                end
                  pl.dirx, pl.diry = 0, 1 
            end
            if key == c.left then 
                for s = 1, moveSpeed do
                    local newX = pl.x - 1
                      if inMap(newX, pl.y) then pl.x = newX end
                end
                pl.dirx, pl.diry = -1, 0 
            end
            if key == c.right then 
                for s = 1, moveSpeed do
                    local newX = pl.x + 1
                    if inMap(newX, pl.y) then pl.x = newX end
                end
                pl.dirx, pl.diry = 1, 0 
            end
            
            if key == c.shoot then 
                local multishot = pl.powerups.multishot or 0
                local dmg = 1 + (pl.powerups.damage or 0)
                local prc = (pl.powerups.pierce or 0) > 0
                local breaksWalls = (pl.powerups.wallbreak or 0) > 0
                if multishot > 0 then
                    table.insert(bullets,{x=pl.x, y=pl.y, dx=pl.dirx, dy=pl.diry, damage=dmg, pierce=prc, breaksWalls=breaksWalls})
                    local side1_dx, side1_dy = -pl.diry, pl.dirx 
                    local side2_dx, side2_dy = pl.diry, -pl.dirx
                     table.insert(bullets,{x=pl.x, y=pl.y, dx=side1_dx, dy=side1_dy, damage=dmg, pierce=prc, breaksWalls=breaksWalls})
                     table.insert(bullets,{x=pl.x, y=pl.y, dx=side2_dx, dy=side2_dy, damage=dmg, pierce=prc, breaksWalls=breaksWalls})
                else
                    table.insert(bullets,{x=pl.x, y=pl.y, dx=pl.dirx, dy=pl.diry, damage=dmg, pierce=prc, breaksWalls=breaksWalls})
                end
                SFX.shoot:stop(); SFX.shoot:play() 
            end
            
            if key == c.build and blocks >= 1 then
                local nx, ny = findFreeCellFromDir(pl.x, pl.y, pl.dirx, pl.diry)
                if nx then 
                    table.insert(walls,{x=pl.x, y=pl.y, hp=5}); 
                    pl.x, pl.y = nx, ny; 
                    blocks = blocks - 1; 
                    SFX.build:play(); 
                    killZombiesInClosedAreas() 
                  end
            end
            ::continue::
        end
    else
        local me = net.role == "host" and players[1] or players[2]
        if me.hp <= 0 then return end
        local c = me.controls
        local moveSpeed = 1 + (me.powerups.speed or 0)
        
        if key == c.up then  
            for s = 1, moveSpeed do 
                local newY = me.y - 1
                if inMap(me.x, newY) then me.y = newY end
            end
             me.dirx, me.diry = 0, -1 
        end
        if key == c.down then 
            for s = 1, moveSpeed do
                local newY = me.y + 1
                if inMap(me.x, newY) then me.y = newY end
            end
            me.dirx, me.diry = 0, 1 
        end
        if key == c.left then 
             for s = 1, moveSpeed do
                local newX = me.x - 1
                if inMap(newX, me.y) then me.x = newX end
            end
             me.dirx, me.diry = -1, 0 
        end
        if key == c.right then 
            for s = 1, moveSpeed do
                local newX = me.x + 1
                if inMap(newX, me.y) then me.x = newX end
            end
            me.dirx, me.diry = 1, 0 
          end
        
        if key == c.shoot then 
            local multishot = me.powerups.multishot or 0
            local dmg = 1 + (me.powerups.damage or 0)
            local prc = (me.powerups.pierce or 0) > 0
            local breaksWalls = (me.powerups.wallbreak or 0) > 0
            if multishot > 0 then
                table.insert(bullets,{x=me.x, y=me.y, dx=me.dirx, dy=me.diry, damage=dmg, pierce=prc, breaksWalls=breaksWalls})
                local side1_dx, side1_dy = -me.diry, me.dirx
                 local side2_dx, side2_dy = me.diry, -me.dirx
                table.insert(bullets,{x=me.x, y=me.y, dx=side1_dx, dy=side1_dy, damage=dmg, pierce=prc, breaksWalls=breaksWalls})
                table.insert(bullets,{x=me.x, y=me.y, dx=side2_dx, dy=side2_dy, damage=dmg, pierce=prc, breaksWalls=breaksWalls})
            else
                table.insert(bullets,{x=me.x, y=me.y, dx=me.dirx, dy=me.diry, damage=dmg, pierce=prc, breaksWalls=breaksWalls})
            end
            SFX.shoot:stop(); SFX.shoot:play() 
        end
        
        if key == c.build and blocks >= 1 then
            local nx, ny = findFreeCellFromDir(me.x, me.y, me.dirx, me.diry)
            if nx then 
                table.insert(walls,{x=me.x, y=me.y, hp=5}); 
                  me.x, me.y = nx, ny; 
                blocks = blocks - 1; 
                SFX.build:play(); 
                killZombiesInClosedAreas() 
            end
        end
     end
end
end
function startLocalGame()
score = 0
gameTimer = 0
spawnTimer = 0
spawnInterval = 2.5
blocks = 8
zombies = {}
bullets = {}
players[1].x, players[1].y = math.floor(MAP_W / 2) - 4, math.floor(MAP_H / 2)
players[2].x, players[2].y = math.floor(MAP_W / 2) + 4, math.floor(MAP_H / 2)
players[1].hp = MAX_HP
players[2].hp = MAX_HP
players[1].dirx, players[1].diry = 1, 0
players[2].dirx, players[2].diry = -1, 0
clearPlayerPowerups()
generateRandomMap()
titleBgm:stop(); SFX.start_game:play(); gameState = "playing"
if musicEnabled then bgm:play() end; if gameMode == "1P" then players[2].hp = 0 end
end
-- ============================================================================
--  update
-- ============================================================================
function love.update(dt)
if gameState == "playing" and gameMode == "online" then
netUpdate(dt)
if not net.peer then return end
if players[2].hp == 0 then players[2].hp = MAX_HP end
netSendInput()
end
if gameState ~= "playing" then return end
for i, pl in ipairs(players) do
    if gameMode == "1P" and i == 2 then break end
    if pl.hp > 0 and pl.hp < MAX_HP and (pl.powerups.regen or 0) > 0 then
        local regenInterval = 3 / (pl.powerups.regen or 0)
        if math.floor(gameTimer / regenInterval) > math.floor((gameTimer - dt) / regenInterval) then
            pl.hp = math.min(MAX_HP, pl.hp + 1)
        end
    end
end

gameTimer = gameTimer + dt; spawnTimer = spawnTimer + dt
if spawnTimer >= spawnInterval then spawnTimer = 0; spawnZombie() end

for i = #bullets, 1, -1 do
    local b = bullets[i]; b.x, b.y = b.x + b.dx * BULLET_SPEED * dt, b.y + b.dy * BULLET_SPEED * dt
    if not inMap(math.floor(b.x), math.floor(b.y)) then table.remove(bullets, i) end
end

for zi = #zombies, 1, -1 do
    local z = zombies[zi]; z.moveTimer = z.moveTimer - dt
      if z.moveTimer <= 0 then
        z.moveTimer = ZOMBIE_MOVE_INTERVAL
        local target; local d1 = (players[1].hp > 0) and (math.abs(players[1].x - z.x) + math.abs(players[1].y - z.y)) or 999
        local d2 = 999; if gameMode == "2P" or (gameMode == "online" and players[2].hp > 0) then d2 = (players[2].hp > 0) and (math.abs(players[2].x - z.x) + math.abs(players[2].y - z.y)) or 999 end
        target = (d1 < d2) and players[1] or players[2]
        local dx = target.x > z.x and 1 or target.x < z.x and -1 or 0
        local dy = target.y > z.y and 1 or target.y < z.y and -1 or 0
        local nx, ny = z.x + dx, z.y + dy; local hit = false
        for i, p in ipairs(players) do
            if gameMode == "1P" and i == 2 then break end
            if p.hp > 0 and nx == p.x and ny == p.y then p.hp = math.max(0, p.hp - 1); SFX.hit:play(); hit = true; checkGameOver() end
        end
        if not hit then
            local w = wallAt(nx, ny)
            local tw = towerWallAt(nx, ny)
            if w then 
                w.hp = w.hp - 1
                if w.hp <= 0 then for j = #walls, 1, -1 do if walls[j] == w then table.remove(walls, j) end end end
            elseif tw then
                tw.hp = tw.hp - 1
                if tw.hp <= 0 then for j = #towerWalls, 1, -1 do if towerWalls[j] == tw then table.remove(towerWalls, j) end end end
            elseif nx == core.x and ny == core.y then
                gameState = "gameover"
                if bgm then bgm:stop() end
                SFX.gameover:play()
                table.remove(zombies, zi)
            else 
                z.x, z.y = nx, ny 
              end
        else table.remove(zombies, zi) end
    end
end

-- 【新增】子弹逻辑：支持破坏墙壁 + 修复原代码 break 误跳问题
for bi = #bullets, 1, -1 do
    local b = bullets[bi]
    local bx, by = math.floor(b.x), math.floor(b.y)
    local removed = false

    -- 1. 检查墙壁碰撞（若携带 Wall Breaker 技能）
    if b.breaksWalls then
        local w = wallAt(bx, by)
        if w then
            w.hp = w.hp - b.damage
            if w.hp <= 0 then for j=#walls,1,-1 do if walls[j]==w then table.remove(walls,j) break end end end
            SFX.wallbreak:stop(); SFX.wallbreak:play()
            if not b.pierce then table.remove(bullets, bi); removed = true end
        end
        if not removed then
            local tw = towerWallAt(bx, by)
            if tw then
                tw.hp = tw.hp - b.damage
                if tw.hp <= 0 then for j=#towerWalls,1,-1 do if towerWalls[j]==tw then table.remove(towerWalls,j) break end end end
                SFX.wallbreak:stop(); SFX.wallbreak:play()
                if not b.pierce then table.remove(bullets, bi); removed = true end
            end
        end
    end
    if removed then goto next_bullet end

    -- 2. 检查僵尸碰撞
    for zi = #zombies, 1, -1 do
        local z = zombies[zi]
        if bx == z.x and by == z.y then
            z.hp = z.hp - b.damage
            if not b.pierce then table.remove(bullets, bi); removed = true end
            if z.hp <= 0 then
                local baseBlocks = z.blocks
                for i, pl in ipairs(players) do
                    if gameMode == "1P" and i == 2 then break end
                    if pl.hp > 0 then baseBlocks = baseBlocks + (pl.powerups.build or 0) * 3 end
                end
                blocks = blocks + baseBlocks
                table.remove(zombies, zi)
                SFX.kill:play()
            end
            if not b.pierce then goto next_bullet end
            break
        end
    end
    ::next_bullet::
end

if gameMode == "online" and net.peer then
    local remote = net.remoteInput; local p2 = players[2]
    if p2.hp > 0 then
        local moveSpeed = 1 + (p2.powerups.speed or 0)
        if remote.up then 
            for s = 1, moveSpeed do
                local newY = p2.y - 1
                  if inMap(p2.x, newY) then p2.y = newY end
            end
            p2.dirx, p2.diry = 0, -1 
        end
        if remote.down then 
            for s = 1, moveSpeed do
                local newY = p2.y + 1
                if inMap(p2.x, newY) then p2.y = newY end
            end
            p2.dirx, p2.diry = 0, 1 
        end
         if remote.left then 
            for s = 1, moveSpeed do
                local newX = p2.x - 1
                if inMap(newX, p2.y) then p2.x = newX end
            end
            p2.dirx, p2.diry = -1, 0 
        end
        if remote.right then 
            for s = 1, moveSpeed do
                local newX = p2.x + 1
                if inMap(newX, p2.y) then p2.x = newX end
            end
            p2.dirx, p2.diry = 1, 0 
        end
        
        if remote.shoot then 
            local multishot = p2.powerups.multishot or 0
            local dmg = 1 + (p2.powerups.damage or 0)
            local prc = (p2.powerups.pierce or 0) > 0
            local breaksWalls = (p2.powerups.wallbreak or 0) > 0
            if multishot > 0 then
                table.insert(bullets,{x=p2.x, y=p2.y, dx=p2.dirx, dy=p2.diry, damage=dmg, pierce=prc, breaksWalls=breaksWalls})
                local side1_dx, side1_dy = -p2.diry, p2.dirx
                 local side2_dx, side2_dy = p2.diry, -p2.dirx
                table.insert(bullets,{x=p2.x, y=p2.y, dx=side1_dx, dy=side1_dy, damage=dmg, pierce=prc, breaksWalls=breaksWalls})
                table.insert(bullets,{x=p2.x, y=p2.y, dx=side2_dx, dy=side2_dy, damage=dmg, pierce=prc, breaksWalls=breaksWalls})
            else
                table.insert(bullets,{x=p2.x, y=p2.y, dx=p2.dirx, dy=p2.diry, damage=dmg, pierce=prc, breaksWalls=breaksWalls})
            end
            SFX.shoot:stop(); SFX.shoot:play() 
        end
        
        if remote.build and blocks >= 1 then
            local nx, ny = findFreeCellFromDir(p2.x, p2.y, p2.dirx, p2.diry)
            if nx then 
                table.insert(walls,{x=p2.x, y=p2.y, hp=5}); 
                  p2.x, p2.y = nx, ny; 
                blocks = blocks - 1; 
                SFX.build:play(); 
                killZombiesInClosedAreas() 
            end
        end
     end
end
end
-- ============================================================================
--  绘制
-- ============================================================================
function love.draw()
local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
local topPadding = 70
love.graphics.clear(0.05, 0.05, 0.08)
if gameState == "start" then
love.graphics.setFont(asciiFont)
local r = 0.5 + math.sin(love.timer.getTime()*2)*0.5
local gColor = {0.3, 1, 0.3 * r + 0.5}
love.graphics.setColor(gColor)
love.graphics.printf(asciiTitle, 0, sh * 0.1, sw, "center")
local titleW = asciiFont:getWidth(asciiTitle)
local lineY = sh * 0.1 + asciiFont:getHeight() + 10
love.graphics.setLineWidth(4)
love.graphics.setColor(gColor[1], gColor[2], gColor[3], 0.8)
love.graphics.line(sw/2 - titleW/2, lineY, sw/2 + titleW/2, lineY)
love.graphics.setColor(gColor[1], gColor[2], gColor[3], 0.4)
love.graphics.line(sw/2 - titleW/2 + 20, lineY + 12, sw/2 + titleW/2 - 20, lineY + 12)
    local menuY = sh * 0.38
    love.graphics.setFont(mediumFont)
    local function drawMenuItem(text, y, selected, colorActive, colorInactive)
        love.graphics.setColor(selected and colorActive or colorInactive)
        love.graphics.printf(selected and "> " .. text .. " <" or text, 0, y, sw, "center")
    end
    drawMenuItem("PLAY", menuY,       currentMenuSelection == 1, {0.3,1,0.3}, {0.3,0.3,0.3})
    drawMenuItem("SETTINGS", menuY + 50, currentMenuSelection == 2, {1,1,0.2},   {0.3,0.3,0.3})
    drawMenuItem("EXIT", menuY + 100, currentMenuSelection == 3, {1,0.3,0.3}, {0.3,0.3,0.3})

    local boxW, boxH = 800, 260
    local boxX, boxY = (sw-boxW)/2, menuY + 180
    love.graphics.setColor(0.1, 0.1, 0.15, 0.8)
    love.graphics.rectangle("fill", boxX, boxY, boxW, boxH, 10)
    love.graphics.setColor(0.3, 0.3, 0.4)
    love.graphics.rectangle("line", boxX, boxY, boxW, boxH, 10)
    love.graphics.setFont(smallFont)
    love.graphics.setColor(0.3, 0.8, 1)
    love.graphics.printf("Use TAB (or Shift+TAB) to navigate", boxX, boxY + 15, boxW, "center")
    love.graphics.setColor(0.2, 0.2, 0.25)
    love.graphics.line(boxX + 20, boxY + 50, boxX + boxW - 20, boxY + 50)
    love.graphics.setColor(0.6, 0.6, 0.6)
    love.graphics.printf("CONTROLS", boxX, boxY + 70, boxW/2, "center")
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("              P1 : W A S D | SPACE | M\n\n              P2 : ARROWS | ENTER | RSHIFT", boxX, boxY + 115, boxW/2, "left")
    love.graphics.setColor(0.6, 0.6, 0.6)
    love.graphics.printf("HOW TO PLAY", boxX + boxW/2, boxY + 70, boxW/2, "center")
    love.graphics.setColor(0.9, 0.9, 0.4)
    love.graphics.printf("1. SHOOT to kill for BLOCKS.\n2. BUILD walls to TRAP.\n3. ENCLOSING grants SCORES!", boxX + boxW/2 + 30, boxY + 115, boxW/2 - 40, "left")
    love.graphics.setColor(1, 1, 1, math.abs(math.sin(love.timer.getTime()*3)))
    love.graphics.setFont(mediumFont)
    love.graphics.printf("Press SPACE / ENTER to Select", 0, sh - 80, sw, "center")
    return
end

if gameState == "play_submenu" then
    love.graphics.setColor(0.05, 0.05, 0.1, 0.95)
    love.graphics.rectangle("fill", 0, 0, sw, sh)
    love.graphics.setFont(mediumFont)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("—  SELECT GAME MODE  —", 0, 60, sw, "center")
    local menuY = sh * 0.35
    local function drawPlayItem(text, y, selected, colorActive, colorInactive)
        love.graphics.setColor(selected and colorActive or colorInactive)
        love.graphics.printf(selected and "> " .. text .. " <" or text, 0, y, sw, "center")
    end
    drawPlayItem("SINGLE PLAYER", menuY,       currentPlaySelection == 1, {0.3,1,0.3}, {0.3,0.3,0.3})
    drawPlayItem("CO-OP MODE",     menuY + 60, currentPlaySelection == 2, {1,1,0.2},   {0.3,0.3,0.3})
    drawPlayItem("ONLINE MODE",    menuY + 120, currentPlaySelection == 3, {0.3,0.3,1}, {0.3,0.3,0.3})

    if currentPlaySelection == 3 then
        local boxW, boxH = 600, 120
        local boxX, boxY = (sw-boxW)/2, menuY + 200
        love.graphics.setColor(0.1, 0.1, 0.2, 0.8)
        love.graphics.rectangle("fill", boxX, boxY, boxW, boxH, 10)
        love.graphics.setColor(0.3, 0.3, 0.4)
        love.graphics.rectangle("line", boxX, boxY, boxW, boxH, 10)
        love.graphics.setFont(smallFont)
        love.graphics.setColor(0.8, 0.8, 0.8)
        love.graphics.printf("Room Name:", boxX, boxY + 15, boxW, "center")
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf(onlineInputBuffer .. (math.floor(love.timer.getTime()*2) % 2 == 0 and "_" or " "), boxX, boxY + 45, boxW, "center")
        if showOnlineError then
            love.graphics.setColor(1, 0.3, 0.3)
            love.graphics.printf(showOnlineError, boxX, boxY + 75, boxW, "center")
        end
        love.graphics.setColor(0.5, 0.5, 0.5)
        love.graphics.printf("TAB to Navigate  |  SPACE to Select  |  ESC to Back", 0, sh - 80, sw, "center")
    else
        local boxW, boxH = 600, 120
        local boxX, boxY = (sw-boxW)/2, menuY + 200
        love.graphics.setColor(0.1, 0.1, 0.2, 0.8)
        love.graphics.rectangle("fill", boxX, boxY, boxW, boxH, 10)
        love.graphics.setColor(0.3, 0.3, 0.4)
        love.graphics.rectangle("line", boxX, boxY, boxW, boxH, 10)
        love.graphics.setFont(smallFont)
        love.graphics.setColor(0.8, 0.8, 0.8)
        local texts = {"Survive alone against endless zombie hordes!", "Team up with a friend in local co-op mode!", "Connect with players worldwide (LAN)!"}
        love.graphics.printf(texts[currentPlaySelection], boxX, boxY + 25, boxW, "center")
        love.graphics.setColor(0.5, 0.5, 0.5)
        love.graphics.printf("TAB to Navigate  |  SPACE to Select  |  ESC to Back", 0, sh - 80, sw, "center")
    end
    return
end

if gameState == "settings" then
    local sw, sh = love.graphics.getDimensions()
    love.graphics.setColor(0.05, 0.05, 0.1, 0.95)
    love.graphics.rectangle("fill", 0, 0, sw, sh)
    love.graphics.setFont(mediumFont)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("—  SYSTEM SETTINGS  —", 0, 60, sw, "center")

    local audioY = 140; local isAudioSelected = (currentSettingSelection == 1)
    love.graphics.setColor(0.1, 0.1, 0.2, 0.8)
    love.graphics.rectangle("fill", sw/2 - 200, audioY - 10, 400, 50, 5)
    love.graphics.setColor(isAudioSelected and {1, 1, 0.3} or {0.7, 0.7, 0.7})
    local audioText = "MUSIC: " .. (musicEnabled and "ON" or "OFF")
    love.graphics.printf(isAudioSelected and "> " .. audioText .. " <" or audioText, 0, audioY, sw, "center")

    local panelW, panelH = 450, 400; local p1X = sw/2 - panelW - 20; local p2X = sw/2 + 20; local keysY = 240; local lineH = 55
    local function drawControlPanel(x, y, title, config, startIdx, color)
        love.graphics.setColor(0.1, 0.1, 0.15, 0.8)
        love.graphics.rectangle("fill", x, y, panelW, panelH, 10)
        love.graphics.setColor(color[1], color[2], color[3], 0.3)
        love.graphics.rectangle("line", x, y, panelW, panelH, 10)
        love.graphics.setFont(smallFont)
        love.graphics.setColor(color)
        love.graphics.printf(title, x, y + 20, panelW, "center")
        love.graphics.line(x + 40, y + 55, x + panelW - 40, y + 55)
        local keys = { "up", "down", "left", "right", "shoot", "build" }
        for i, k in ipairs(keys) do
            local itemIdx = startIdx + i; local isSelected = (currentSettingSelection == itemIdx)
            local itemY = y + 70 + (i-1) * lineH
            if isSelected then
                love.graphics.setColor(1, 1, 0.3, 0.2)
                love.graphics.rectangle("fill", x + 10, itemY - 5, panelW - 20, lineH - 5, 5)
                love.graphics.setColor(1, 1, 0.4)
            else
                love.graphics.setColor(0.8, 0.8, 0.8)
              end
            love.graphics.printf(string.upper(k), x + 40, itemY, panelW, "left")
            love.graphics.printf(niceKeyName(config[k]), x - 40, itemY, panelW, "right")
        end
    end
    drawControlPanel(p1X, keysY, "PLAYER 1 (LEFT SIDE)", keyConfig.p1, 1, {0.3, 1, 0.3})
    drawControlPanel(p2X, keysY, "PLAYER 2 (RIGHT SIDE)", keyConfig.p2, 7, {1, 1, 0.2})

    love.graphics.setFont(smallFont)
    love.graphics.setColor(0.5, 0.5, 0.5)
    love.graphics.printf("TAB to Navigate  |  SPACE to Edit  |  ESC to Save & Back", 0, sh - 80, sw, "center")

    if waitingForKey then
        love.graphics.setColor(0, 0, 0, 0.8)
        love.graphics.rectangle("fill", 0, 0, sw, sh)
        love.graphics.setFont(mediumFont)
        love.graphics.setColor(1, 1, 0.5)
        love.graphics.printf("REBINDING KEY...", 0, sh/2 - 50, sw, "center")
        love.graphics.setFont(smallFont)
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf("Press any key for the selected action", 0, sh/2 + 20, sw, "center")
    end
    return
end

if gameState == "powerup_select" then
    love.graphics.setColor(0.05, 0.05, 0.1, 0.95)
    love.graphics.rectangle("fill", 0, 0, sw, sh)
    love.graphics.setFont(mediumFont)
    love.graphics.setColor(1, 0.8, 0.2)
    love.graphics.printf("—  SCORE 200 REACHED! CHOOSE POWERUP  —", 0, sh * 0.2, sw, "center")
    local menuY = sh * 0.35
    local function drawPowerupItem(idx, p, y, selected, colorActive, colorInactive)
        local lvl = (players[1].powerups[p.id] or 0) + 1
         local text = string.format("%s Lv.%d - %s", p.name, lvl, p.desc)
        love.graphics.setColor(selected and colorActive or colorInactive)
        love.graphics.printf(selected and "> " .. text .. " <" or "    " .. text, 0, y, sw, "center")
    end
    for i = 1, 3 do
        local p = powerupSelection.options[i]
        if p then drawPowerupItem(i, p, menuY + (i-1)*60, powerupSelection.selectedIndex == i, {0.3,1,0.3}, {0.5,0.5,0.5}) end
    end
    love.graphics.setFont(smallFont)
    love.graphics.setColor(0.5, 0.5, 0.5)
    love.graphics.printf("TAB to Navigate  |  ENTER to Select", 0, sh - 80, sw, "center")
    return
end

-- ========================= 游戏渲染 =========================
love.graphics.setScissor(0, topPadding, sw, sh - topPadding)
local function cell(x, y, c)
    love.graphics.setColor(c)
    love.graphics.rectangle("fill", x * GRID, y * GRID + topPadding, GRID, GRID)
end
for _, w in ipairs(walls)   do cell(w.x, w.y, {0.5, 0.5, 0.5}) end
for _, tw in ipairs(towerWalls) do cell(tw.x, tw.y, {1.0, 1.0, 1.0}) end
cell(core.x, core.y, {1.0, 0.4, 1})
for _, b in ipairs(bullets) do cell(math.floor(b.x), math.floor(b.y), {1, 1, 1}) end
for _, z in ipairs(zombies) do cell(z.x, z.y, z.color) end
if players[1].hp > 0 then cell(players[1].x, players[1].y, players[1].color) end
if (gameMode == "2P" or (gameMode == "online" and players[2].hp > 0)) then cell(players[2].x, players[2].y, players[2].color) end
love.graphics.setScissor()

local yPos = 25; local hpWidth, hpHeight = GRID - 2, GRID / 2
local function drawPlayerIndicator(x, y, current, max, color, isRightAligned)
    local spacing = 4
    for i = 1, max do
        local drawX = isRightAligned and (x - (i * (hpWidth + spacing))) or (x + (i - 1) * (hpWidth + spacing))
        love.graphics.setColor(i <= current and color or {0.15, 0.15, 0.15})
        love.graphics.rectangle("fill", drawX, y + (hpHeight/2), hpWidth, hpHeight)
    end
end
drawPlayerIndicator(25, yPos, players[1].hp, MAX_HP, players[1].color, false)
local midText = string.format("WALLS: %d | %02d:%02d | SCORE: %d", blocks, math.floor(gameTimer/60), math.floor(gameTimer%60), score)
love.graphics.setFont(mediumFont); love.graphics.setColor(1,1,1); love.graphics.printf(midText, 0, yPos, sw, "center")
if gameMode == "2P" or gameMode == "online" then drawPlayerIndicator(sw - 25, yPos, players[2].hp, MAX_HP, players[2].color, true) end

local activePowerups = {}
for id, level in pairs(players[1].powerups) do
     if level > 0 then
        for _, p in ipairs(POWERUP_TYPES) do
            if p.id == id then
                table.insert(activePowerups, {name = p.name, level = level, color = p.color})
                  break
            end
        end
    end
end

if #activePowerups > 0 then
    love.graphics.setFont(smallFont)
    local startY = yPos + 40
    for i, p in ipairs(activePowerups) do
        love.graphics.setColor(p.color)
        love.graphics.printf(p.name .. " Lv. " .. p.level, 25, startY + (i-1) * 20, 200, "left")
    end
end

if gameState == "gameover" then
    love.graphics.setColor(0, 0, 0, 0.85)
    love.graphics.rectangle("fill", 0, 0, sw, sh)
    love.graphics.setFont(overFont); love.graphics.setColor(1, 0, 0)
    love.graphics.printf("GAME OVER", 0, sh/2 - 100, sw, "center")
    love.graphics.setFont(mediumFont); love.graphics.setColor(1, 1, 1)
    love.graphics.printf("Final Score: "..score.."\nPress ESC to Exit", 0, sh/2 + 50, sw, "center")
end

if gameMode == "online" and gameState == "playing" and not net.peer then
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 0, 0, sw, sh)
    love.graphics.setFont(mediumFont)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("Waiting for players…   " .. net.roomName, 0, sh/2 - 50, sw, "center")
    love.graphics.setFont(smallFont)
    love.graphics.printf("Ensure the other computer uses the same room name.", 0, sh/2 + 20, sw, "center")
end
end