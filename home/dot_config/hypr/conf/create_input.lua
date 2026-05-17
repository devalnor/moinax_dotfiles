-- For all categories, see https://wiki.hypr.land/Configuring/Basics/Variables/
-- Runtime-overwritten by ~/.config/hypr/scripts/toggle-keyboard-layout.sh
-- from one of conf/input-layouts/*.lua. The initial content here is the default
-- layout (fr); edit the layout files in input-layouts/ rather than this file.
hl.config({
    input = {
        kb_layout  = "fr",
        kb_variant = "",
        kb_model   = "",
        kb_options = "",
        kb_rules   = "",

        follow_mouse  = 1,
        mouse_refocus = false,

        touchpad = {
            natural_scroll = true,
        },

        sensitivity = 0, -- -1.0 - 1.0, 0 means no modification.
    },
})
