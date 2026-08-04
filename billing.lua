--------------------------------------------------------
-- billing.lua
-- Cross-platform billing facade
--------------------------------------------------------

local platform = system.getInfo("platformName") or ""

local impl

if platform == "Android" then
    impl = require("billing_google")
elseif platform == "iPhone OS" then
    impl = require("billing_apple")
else
    -- Fallback to Apple-style stub for unsupported platforms/simulator
    impl = require("billing_apple")
end

return impl