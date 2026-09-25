-- Dismiss the screensaver on mouse motion after a short grace period.
-- Clicks/keys are also bound here so dismiss still works if input.conf is missing.

local grace = true
local origin = nil

local function quit()
    mp.command("quit")
end

mp.add_timeout(1.0, function()
    grace = false
end)

mp.observe_property("mouse-pos", "native", function(_, pos)
    if grace or not pos then
        return
    end
    if not origin then
        origin = pos
        return
    end
    local dx = math.abs((pos.x or 0) - (origin.x or 0))
    local dy = math.abs((pos.y or 0) - (origin.y or 0))
    if dx > 8 or dy > 8 then
        quit()
    end
end)

local keys = {
    "MBTN_LEFT", "MBTN_RIGHT", "MBTN_MID", "MBTN_BACK", "MBTN_FORWARD",
    "WHEEL_UP", "WHEEL_DOWN", "WHEEL_LEFT", "WHEEL_RIGHT",
    "ESC", "q", "SPACE", "ENTER", "ANY_UNICODE",
}
for _, key in ipairs(keys) do
    mp.add_forced_key_binding(key, "ss-quit-" .. key, quit)
end
