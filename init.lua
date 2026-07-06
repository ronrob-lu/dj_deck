-- djdeck: A Minetest mod that adds a DJ deck (loudspeaker, turntable, mixer).

djdeck = {}
djdeck.tracks = {}
djdeck.playing_sounds = {}

local modpath = minetest.get_modpath(minetest.get_current_modname())
local sounds_dir = modpath .. "/sounds"

local files = minetest.get_dir_list(sounds_dir, false)
if files then
    for _, filename in ipairs(files) do
        if filename:sub(-4):lower() == ".ogg" then
            local sound_name = filename:sub(1, -5)
            table.insert(djdeck.tracks, sound_name)
        end
    end
end

minetest.register_node("djdeck:loudspeaker", {
    description = "DJ Deck Loudspeaker",
    tiles = {
        "djdeck_loudspeaker_side.png",
        "djdeck_loudspeaker_side.png",
        "djdeck_loudspeaker_side.png",
        "djdeck_loudspeaker_side.png",
        "djdeck_loudspeaker_side.png",
        "djdeck_loudspeaker_front.png"
    },
    paramtype2 = "facedir",
    groups = {choppy = 2, oddly_breakable_by_hand = 2},
})

minetest.register_node("djdeck:turntable", {
    description = "DJ Deck Turntable",
    tiles = {
        "djdeck_turntable_top.png",
        "djdeck_turntable_side.png",
        "djdeck_turntable_side.png",
        "djdeck_turntable_side.png",
        "djdeck_turntable_side.png",
        "djdeck_turntable_side.png"
    },
    paramtype2 = "facedir",
    groups = {choppy = 2, oddly_breakable_by_hand = 2},
    on_construct = function(pos)
        local meta = minetest.get_meta(pos)
        meta:set_string("selected_track", "")
        meta:set_int("selected_idx", 1)
        meta:set_string("infotext", "Turntable (No track)")

        local list_elements = table.concat(djdeck.tracks, ",")
        local formspec = "size[8,6]" ..
            "label[0,0;Select Track]" ..
            "textlist[0,0.5;7.8,5;tracklist;" .. list_elements .. ";1;false]"
        meta:set_string("formspec", formspec)
    end,
    on_receive_fields = function(pos, formname, fields, sender)
        local meta = minetest.get_meta(pos)
        if fields.tracklist then
            local event = core.explode_textlist_event(fields.tracklist)
            if event.type == "CHG" or event.type == "DCL" then
                meta:set_int("selected_idx", event.index)
                local track = djdeck.tracks[event.index]
                if track then
                    meta:set_string("selected_track", track)

                    local display_name = track:gsub("^ve_radio_", ""):gsub("_", " "):upper()
                    meta:set_string("infotext", "Turntable: " .. display_name)

                    -- Re-render formspec to update selected index
                    local list_elements = table.concat(djdeck.tracks, ",")
                    local formspec = "size[8,6]" ..
                        "label[0,0;Select Track]" ..
                        "textlist[0,0.5;7.8,5;tracklist;" .. list_elements .. ";" .. event.index .. ";false]"
                    meta:set_string("formspec", formspec)
                end
            end
        end
    end,
})

minetest.register_node("djdeck:mixer", {
    on_destruct = function(pos)
        local pos_hash = minetest.hash_node_position(pos)
        if djdeck.playing_sounds[pos_hash] then
            if djdeck.playing_sounds[pos_hash].left then minetest.sound_stop(djdeck.playing_sounds[pos_hash].left) end
            if djdeck.playing_sounds[pos_hash].right then minetest.sound_stop(djdeck.playing_sounds[pos_hash].right) end
            djdeck.playing_sounds[pos_hash] = nil
        end
    end,
    description = "DJ Deck Mixer",
    tiles = {
        "djdeck_mixer_top.png",
        "djdeck_mixer_side.png",
        "djdeck_mixer_side.png",
        "djdeck_mixer_side.png",
        "djdeck_mixer_side.png",
        "djdeck_mixer_side.png"
    },
    paramtype2 = "facedir",
    groups = {choppy = 2, oddly_breakable_by_hand = 2},
    on_construct = function(pos)
        local meta = minetest.get_meta(pos)
        meta:set_int("volume", 500)
        meta:set_int("crossfader", 500)

        local formspec = "size[8,6]" ..
            "label[1,0.5;Master Volume]" ..
            "scrollbaroptions[min=0;max=1000;smallstep=10;largestep=100]" ..
            "scrollbar[1,1;6,0.5;horizontal;vol_bar;500]" ..
            "label[1,2.5;Crossfader (Left to Right)]" ..
            "scrollbaroptions[min=0;max=1000;smallstep=10;largestep=100]" ..
            "scrollbar[1,3;6,0.5;horizontal;fade_bar;500]" ..
            "button[2,4.5;2,1;btn_play;Play]" ..
            "button[4,4.5;2,1;btn_stop;Stop]"
        meta:set_string("formspec", formspec)
    end,
    on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
    end,

    on_receive_fields = function(pos, formname, fields, sender)
        local meta = minetest.get_meta(pos)

        -- Update scrollbar states
        if fields.vol_bar then
            local event = core.explode_scrollbar_event(fields.vol_bar)
            if event.type == "CHG" then
                meta:set_int("volume", event.value)
            end
        end
        if fields.fade_bar then
            local event = core.explode_scrollbar_event(fields.fade_bar)
            if event.type == "CHG" then
                meta:set_int("crossfader", event.value)
            end
        end

        if fields.btn_stop then
            local pos_hash = minetest.hash_node_position(pos)
            if djdeck.playing_sounds[pos_hash] then
                if djdeck.playing_sounds[pos_hash].left then minetest.sound_stop(djdeck.playing_sounds[pos_hash].left) end
                if djdeck.playing_sounds[pos_hash].right then minetest.sound_stop(djdeck.playing_sounds[pos_hash].right) end
                djdeck.playing_sounds[pos_hash] = nil
            end
            meta:set_string("infotext", "DJ Mixer (Stopped)")
            return
        end

        if fields.btn_play then
            -- Check structure: Left to Right on X axis or Z axis
            -- Sequence: loudspeaker, turntable, mixer, turntable, loudspeaker
            local axes = {
                {x = 1, y = 0, z = 0},
                {x = 0, y = 0, z = 1}
            }

            local valid_structure = false
            local left_turntable_pos = nil
            local right_turntable_pos = nil

            for _, dir in ipairs(axes) do
                -- Check negative direction
                local n2 = core.get_node({x = pos.x - dir.x, y = pos.y, z = pos.z - dir.z})
                local n3 = core.get_node({x = pos.x - dir.x*2, y = pos.y, z = pos.z - dir.z*2})

                -- Check positive direction
                local p2 = core.get_node({x = pos.x + dir.x, y = pos.y, z = pos.z + dir.z})
                local p3 = core.get_node({x = pos.x + dir.x*2, y = pos.y, z = pos.z + dir.z*2})

                if n2.name == "djdeck:turntable" and n3.name == "djdeck:loudspeaker" and
                   p2.name == "djdeck:turntable" and p3.name == "djdeck:loudspeaker" then
                   valid_structure = true
                   left_turntable_pos = {x = pos.x - dir.x, y = pos.y, z = pos.z - dir.z}
                   right_turntable_pos = {x = pos.x + dir.x, y = pos.y, z = pos.z + dir.z}
                   break
                end
            end

            if not valid_structure then
                minetest.chat_send_player(sender:get_player_name(), "DJ Deck structure invalid. Must be: Loudspeaker -> Turntable -> Mixer -> Turntable -> Loudspeaker in a straight line.")
                return
            end

            -- Stop any existing playback on this mixer
            local pos_hash = minetest.hash_node_position(pos)
            if djdeck.playing_sounds[pos_hash] then
                if djdeck.playing_sounds[pos_hash].left then minetest.sound_stop(djdeck.playing_sounds[pos_hash].left) end
                if djdeck.playing_sounds[pos_hash].right then minetest.sound_stop(djdeck.playing_sounds[pos_hash].right) end
                djdeck.playing_sounds[pos_hash] = nil
            end

            -- Read track selections
            local left_meta = minetest.get_meta(left_turntable_pos)
            local right_meta = minetest.get_meta(right_turntable_pos)

            local left_track = left_meta:get_string("selected_track")
            local right_track = right_meta:get_string("selected_track")

            if left_track == "" and right_track == "" then
                minetest.chat_send_player(sender:get_player_name(), "No tracks selected on turntables.")
                return
            end

            -- Calculate volume gains based on master volume and crossfader
            -- volume ranges 0-1000, crossfader ranges 0-1000 (0=left, 500=center, 1000=right)
            local master_vol = meta:get_int("volume") / 1000.0
            local crossfader = meta:get_int("crossfader") / 1000.0

            local left_gain = master_vol * (1.0 - math.max(0, (crossfader - 0.5) * 2))
            local right_gain = master_vol * (1.0 - math.max(0, (0.5 - crossfader) * 2))

            local handles = {}
            if left_track ~= "" then
                handles.left = core.sound_play(left_track, {
                    pos = left_turntable_pos,
                    gain = left_gain,
                    max_hear_distance = 32,
                    loop = true
                })
            end

            if right_track ~= "" then
                handles.right = core.sound_play(right_track, {
                    pos = right_turntable_pos,
                    gain = right_gain,
                    max_hear_distance = 32,
                    loop = true
                })
            end

            djdeck.playing_sounds[pos_hash] = handles
            meta:set_string("infotext", "DJ Mixer (Playing)")
        end
    end,
})
