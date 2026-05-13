-- See https://wiki.hypr.land/Configuring/Basics/Variables/ for more
hl.config({
    general = {
        gaps_in     = 4,
        gaps_out    = 8,
        border_size = 4,
        ["col.active_border"]   = { colors = { "rgba(ff64ff80)", "rgba(9696ffff)" }, angle = 45 },
        ["col.inactive_border"] = "rgba(6464ff4d)",
        layout            = "dwindle",
        resize_on_border  = true,
    },
    group = {
        auto_group              = true,
        ["col.border_active"]   = { colors = { "rgba(ff64ff80)", "rgba(9696ffff)" }, angle = 45 },
        ["col.border_inactive"] = "rgba(6464ff4d)",
        groupbar = {
            font_size       = 16,
            height          = 16,
            text_offset     = 0,
            ["col.active"]   = "rgba(ff64ff80)",
            ["col.inactive"] = "rgba(6464ff22)",
            indicator_gap    = -20,
            indicator_height = 24,
            keep_upper_gap   = false,
            rounding         = 8,
            round_only_edges          = false,
            gradient_round_only_edges = false,
        },
    },
})
