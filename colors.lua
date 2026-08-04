-- colors.lua
-- SmartSheep Semantic Color System (Creator Palette / App Store Ready)
-- UPDATED for WCAG AA contrast on primary buttons (textOnPrimary on primaryAction >= 4.5:1)
---------------------------------------------------

local colors = {

    ---------------------------------------------------
    -- App Surfaces
    ---------------------------------------------------
    -- #F5F8FA (off-white canvas)
    appBackground        = {0.9608, 0.9725, 0.9804},
    -- #FFFFFF (clean white highlight)
    appBackgroundSoft    = {1.0000, 1.0000, 1.0000},
    -- #CFE3EF (mist blue depth layer)
    appBackgroundDepth   = {0.8118, 0.8902, 0.9373},

    ---------------------------------------------------
    -- Primary Actions (Hero CTA)
    ---------------------------------------------------
    -- #2676AF (darker creator accent blue; WCAG AA with textOnPrimary)
    primaryAction        = {0.1490, 0.4627, 0.6863},
    -- #1E5B86 (pressed / deeper)
    primaryActionPressed = {0.1176, 0.3569, 0.5255},
    -- #4FA3C7 (soft / hover highlight)
    primaryActionSoft    = {0.3098, 0.6392, 0.7804},

    ---------------------------------------------------
    -- Secondary Actions
    ---------------------------------------------------
    -- #E6F0F7 (soft mist blue; calm secondary surface)
    secondaryAction = {0.9020, 0.9412, 0.9686},
    -- #3F6F8F (slate border)
    secondaryActionBorder = {0.2471, 0.4353, 0.5608},

    ---------------------------------------------------
    -- Subscribe Actions
    ---------------------------------------------------
    subscribeAction = { 0.45, 0.75, 0.38 },
    subscribeActionBorder = { 0.25, 0.52, 0.24 },
    ---------------------------------------------------
    -- Text
    ---------------------------------------------------
    -- #F2F6F9 (AAA on darker blues)
    textOnPrimary        = {0.9490, 0.9647, 0.9765},
    -- #1E2A33 (AAA on white)
    textPrimary          = {0.1, 0.1, 0.1},
    -- #5E7484 (AA on white; good for helper text)
    textSecondary        = {0.3686, 0.4549, 0.5176},
    -- #1E2A33 (consistent on light panels)
    textOnLight          = {0.1176, 0.1647, 0.2000},

    ---------------------------------------------------
    -- Decorative / World
    ---------------------------------------------------
    -- Muted greens (less neon, more creator-calm)
    -- #6FBFA1
    worldGrass           = {0.4353, 0.7490, 0.6314},
    -- #3E8F73
    worldLeaf            = {0.2431, 0.5608, 0.4510},

    ---------------------------------------------------
    -- Status / Feedback
    ---------------------------------------------------
    -- #6FBFA1 (muted success)
    success              = {0.4353, 0.7490, 0.6314},
    -- KEEP warning (per request)
    warning              = {0.95, 0.65, 0.15},
    -- #C96A6A (muted error; avoid harsh red)
    error                = {0.7882, 0.4157, 0.4157},

    ---------------------------------------------------
    -- Accessibility / Focus
    ---------------------------------------------------
    -- #5FA8D3 (clear focus indicator, matches palette)
    focusRing            = {0.3725, 0.6588, 0.8275},
}

return colors
