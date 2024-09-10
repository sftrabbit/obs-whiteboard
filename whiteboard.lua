-- OBS Whiteboard Script
-- Authors: Mike Welsh (mwelsh@gmail.com), Tari
-- v1.3


obs             = obslua
hotkey_clear    = obs.OBS_INVALID_HOTKEY_ID
hotkey_color    = obs.OBS_INVALID_HOTKEY_ID
hotkey_size     = obs.OBS_INVALID_HOTKEY_ID
hotkey_erase    = obs.OBS_INVALID_HOTKEY_ID
hotkey_undo     = obs.OBS_INVALID_HOTKEY_ID
needs_clear     = false
swap_color      = false
toggle_size     = false
eraser          = false
scene_name      = nil
setting_update  = false

eraser_v4     = obs.vec4()
color_index   = 1
-- Preset colors: Yellow, Red, Green, Blue, White, Custom (format is 0xABGR)
color_array = {0xff4d4de8, 0xff4d9de8, 0xff4de5e8, 0xff4de88e, 0xff95e84d, 0xffe8d34d, 0xffe8574d, 0xffe84d9d, 0xffbc4de8}
draw_size     = 6
eraser_size   = 18
size_max      = 12  -- size_max must be a minimum of 2.

eraser_vert = obs.gs_vertbuffer_t
dot_vert = obs.gs_vertbuffer_t
line_vert = obs.gs_vertbuffer_t

drawing = false
lines = {}

target_window = nil

bit = require("bit")
winapi = require("winapi")
require("winapi.cursor")
require("winapi.keyboard")
require("winapi.window")
require("winapi.winbase")

local source_def = {}
source_def.id = "whiteboard"
source_def.output_flags = bit.bor(obs.OBS_SOURCE_VIDEO, obs.OBS_SOURCE_CUSTOM_DRAW)

source_def.get_name = function()
    return "Whiteboard"
end

source_def.create = function(source, settings)
    local data = {}
    
    data.active = false
    
    obs.vec4_from_rgba(eraser_v4, 0x00000000)
    
    data.prev_mouse_pos = nil
    
    -- Create the vertices needed to draw our lines.
    update_vertices()

    local video_info = obs.obs_video_info()
    if obs.obs_get_video_info(video_info) then
        data.width = video_info.base_width
        data.height = video_info.base_height

        create_textures(data)
    else
        print "Failed to get video resolution"
    end

    return data
end

source_def.destroy = function(data)
    data.active = false
    obs.obs_enter_graphics()
    obs.gs_texture_destroy(data.canvas_texture)
    obs.gs_texture_destroy(data.ui_texture)
    obs.obs_leave_graphics()
end

-- A function named script_load will be called on startup
function script_load(settings)
    hotkey_clear = obs.obs_hotkey_register_frontend("whiteboard.clear", "Clear Whiteboard", clear)
    if hotkey_clear == nil then
        hotkey_clear = obs.OBS_INVALID_HOTKEY_ID
    end
    local hotkey_save_array = obs.obs_data_get_array(settings, "whiteboard.clear")
    obs.obs_hotkey_load(hotkey_clear, hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)
    
    hotkey_undo = obs.obs_hotkey_register_frontend("whiteboard.undo", "Undo Whiteboard", undo)
    if hotkey_undo == nil then
        hotkey_undo = obs.OBS_INVALID_HOTKEY_ID
    end
    local hotkey_save_array5 = obs.obs_data_get_array(settings, "whiteboard.undo")
    obs.obs_hotkey_load(hotkey_undo, hotkey_save_array5)
    obs.obs_data_array_release(hotkey_save_array5)
end

function script_update(settings)
    -- Set setting_update to true in order to trigger an update to the
    -- vertices used to draw our lines. This is deferred to the graphics
    -- loop (in source_def.video_tick()) to avoid potential race
    -- conditions.
    setting_update = true
end

-- A function named script_save will be called when the script is saved
--
-- NOTE: This function is usually used for saving extra data (such as in this
-- case, a hotkey's save data).  Settings set via the properties are saved
-- automatically.
function script_save(settings)
    local hotkey_save_array = obs.obs_hotkey_save(hotkey_clear)
    obs.obs_data_set_array(settings, "whiteboard.clear", hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)
    
    hotkey_save_array = obs.obs_hotkey_save(hotkey_size)
    obs.obs_data_set_array(settings, "whiteboard.sizetoggle", hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)
    
    hotkey_save_array = obs.obs_hotkey_save(hotkey_undo)
    obs.obs_data_set_array(settings, "whiteboard.undo", hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)
end

source_def.video_tick = function(data, dt)
    local video_info = obs.obs_video_info()

    -- Check to see if stream resoluiton resized and recreate texture if so
    -- TODO: Is there a signal that does this?
    if obs.obs_get_video_info(video_info) and (video_info.base_width ~= data.width or video_info.base_height ~= data.height) then
        data.width = video_info.base_width
        data.height = video_info.base_height
        create_textures(data)
    end

    if data.canvas_texture == nil or data.ui_texture == nil then
        return
    end
    
    if not data.active then
        return
    end

    if needs_clear then
        local prev_render_target = obs.gs_get_render_target()
        local prev_zstencil_target = obs.gs_get_zstencil_target()

        obs.gs_viewport_push()
        obs.gs_set_viewport(0, 0, data.width, data.height)

        obs.obs_enter_graphics()
        obs.gs_set_render_target(data.canvas_texture, nil)
        obs.gs_clear(obs.GS_CLEAR_COLOR, obs.vec4(), 1.0, 0)

        draw_lines(data, lines)

        obs.gs_viewport_pop()
        obs.gs_set_render_target(prev_render_target, prev_zstencil_target)

        obs.obs_leave_graphics()

        needs_clear = false
    end

    local prev_render_target = obs.gs_get_render_target()
    local prev_zstencil_target = obs.gs_get_zstencil_target()

    obs.gs_viewport_push()
    obs.gs_set_viewport(0, 0, data.width, data.height)

    obs.obs_enter_graphics()
    obs.gs_set_render_target(data.ui_texture, nil)
    obs.gs_clear(obs.GS_CLEAR_COLOR, obs.vec4(), 1.0, 0)

    obs.gs_viewport_pop()
    obs.gs_set_render_target(prev_render_target, prev_zstencil_target)

    obs.obs_leave_graphics()

    local mouse_down = winapi.GetAsyncKeyState(winapi.VK_LBUTTON)
    local window = winapi.GetForegroundWindow()
    if mouse_down then
        if is_drawable_window(window) then
            target_window = window
        else
            target_window = nil
        end
    end

    if not drawing and window == target_window then
        update_color()
        update_size()
    end

    if mouse_down then
        if window and window == target_window then
            local mouse_pos = get_mouse_pos(data, window)

            local size = draw_size
            if color_index == 0 then
                size = eraser_size
            end
            
            if drawing then
                effect = obs.obs_get_base_effect(obs.OBS_EFFECT_DEFAULT)
                if not effect then
                    return
                end

                local new_segment = {
                    color = color_index,
                    size = size,
                    points = {
                        { x = data.prev_mouse_pos.x, y = data.prev_mouse_pos.y },
                        { x = mouse_pos.x, y = mouse_pos.y }
                    }
                }
                draw_lines(data, { new_segment })
                table.insert(lines[#lines].points, { x = mouse_pos.x, y = mouse_pos.y })
            else
                if valid_position(mouse_pos.x, mouse_pos.y, data.width, data.height) then
                    table.insert(lines, {
                        color = color_index,
                        size = size,
                        points = {{ x = mouse_pos.x, y = mouse_pos.y }}
                    })
                    drawing = true
                end
            end

            data.prev_mouse_pos = mouse_pos
        end
    end

    if window and window == target_window then
        local mouse_pos = get_mouse_pos(data, window)
        if valid_position(mouse_pos.x, mouse_pos.y, data.width, data.height) then
            draw_cursor(data, mouse_pos)
        end
    end

    if not mouse_down then
        if data.prev_mouse_pos then
            data.prev_mouse_pos = nil
            drawing = false
        end
    end
end

function update_color()
    for i=0,#color_array do
        local key_down = winapi.GetAsyncKeyState(0x30 + i)
        if key_down then
            color_index = i
        end
    end
end

function update_size()
    local size_changed = false

    local plus_down = winapi.GetAsyncKeyState(winapi.VK_OEM_PLUS)
    if plus_down then
        if not plus_pressed and draw_size < 100 then
            if color_index == 0 then
                eraser_size = eraser_size + 4
            else
                draw_size = draw_size + 4
            end
            size_changed = true
            plus_pressed = true
        end
    else
        plus_pressed = false
    end

    local minus_down = winapi.GetAsyncKeyState(winapi.VK_OEM_MINUS)
    if minus_down then
        if not minus_pressed and draw_size > 3 then
            if color_index == 0 then
                eraser_size = eraser_size - 4
            else
                draw_size = draw_size - 4
            end
            size_changed = true
            minus_pressed = true
        end
    else
        minus_pressed = false
    end
end

function is_drawable_window(window)
    window_name = winapi.InternalGetWindowText(window, nil)
    if not window_name then
        return false
    end

    return window_match(window_name) and
        (string.find(window_name, "Windowed Projector", 1, true) or
        string.find(window_name, "Fullscreen Projector", 1, true))
end

function get_mouse_pos(data, window)
    local mouse_pos = winapi.GetCursorPos()
    winapi.ScreenToClient(window, mouse_pos)

    local window_rect = winapi.GetClientRect(window)
    
    local output_aspect = data.width / data.height

    local window_width = window_rect.right - window_rect.left
    local window_height = window_rect.bottom - window_rect.top
    local window_aspect = window_width / window_height
    local offset_x = 0
    local offset_y = 0
    if window_aspect >= output_aspect then
        offset_x = (window_width - window_height * output_aspect) / 2
    else
        offset_y = (window_height - window_width / output_aspect) / 2
    end

    mouse_pos.x = data.width * (mouse_pos.x - offset_x) / (window_width - offset_x*2)
    mouse_pos.y = data.height * (mouse_pos.y - offset_y) / (window_height - offset_y*2)

    return mouse_pos
end

function draw_lines(data, lines)
    obs.obs_enter_graphics()

    local prev_render_target = obs.gs_get_render_target()
    local prev_zstencil_target = obs.gs_get_zstencil_target()

    obs.gs_set_render_target(data.canvas_texture, nil)
    obs.gs_viewport_push()
    obs.gs_set_viewport(0, 0, data.width, data.height)
    obs.gs_projection_push()
    obs.gs_ortho(0, data.width, 0, data.height, 0.0, 1.0)

    for _, line in ipairs(lines) do
        if #(line.points) > 1 then
            obs.gs_blend_state_push()
            obs.gs_reset_blend_state()
            
            -- Set the color being used (or set the eraser).
            local solid = obs.obs_get_base_effect(obs.OBS_EFFECT_SOLID)
            local color = obs.gs_effect_get_param_by_name(solid, "color")
            local tech  = obs.gs_effect_get_technique(solid, "Solid")

            if line.color == 0 then
                obs.gs_blend_function(obs.GS_BLEND_SRCALPHA, obs.GS_BLEND_SRCALPHA)
                obs.gs_effect_set_vec4(color, eraser_v4)
            else
                local color_v4 = obs.vec4()
                obs.vec4_from_rgba(color_v4, color_array[line.color])
                obs.gs_effect_set_vec4(color, color_v4)
            end

            obs.gs_technique_begin(tech)
            obs.gs_technique_begin_pass(tech, 0)

            for i=1, (#(line.points) - 1) do
                local start_pos = line.points[i]
                local end_pos = line.points[i+1]

                -- Calculate distance mouse has traveled since our
                -- last update.
                local dx = end_pos.x - start_pos.x
                local dy = end_pos.y - start_pos.y
                local len = math.sqrt(dx*dx + dy*dy)
                local angle = math.atan2(dy, dx)
                
                -- Perform matrix transformations for the dot at the
                -- start of the line (start cap).
                obs.gs_matrix_push()
                obs.gs_matrix_identity()
                obs.gs_matrix_translate3f(start_pos.x, start_pos.y, 0)

                obs.gs_matrix_push()
                obs.gs_matrix_scale3f(line.size, line.size, 1.0)
                
                -- Draw start of line.
                obs.gs_load_vertexbuffer(dot_vert)
                obs.gs_draw(obs.GS_TRIS, 0, 0)

                obs.gs_matrix_pop()

                -- Perform matrix transformations for the actual line.
                obs.gs_matrix_rotaa4f(0, 0, 1, angle)
                obs.gs_matrix_translate3f(0, -line.size, 0)
                obs.gs_matrix_scale3f(len, line.size, 1.0)

                -- Draw actual line.
                obs.gs_load_vertexbuffer(line_vert)
                obs.gs_draw(obs.GS_TRIS, 0, 0)

                -- Perform matrix transforms for the dot at the end
                -- of the line (end cap).
                obs.gs_matrix_identity()
                obs.gs_matrix_translate3f(end_pos.x, end_pos.y, 0)
                obs.gs_matrix_scale3f(line.size, line.size, 1.0)
                obs.gs_load_vertexbuffer(dot_vert)
                obs.gs_draw(obs.GS_TRIS, 0, 0)

                obs.gs_matrix_pop()
            end

            -- Done drawing line, restore everything.
            obs.gs_technique_end_pass(tech)
            obs.gs_technique_end(tech)

            obs.gs_blend_state_pop()
        end
    end

    obs.gs_projection_pop()
    obs.gs_viewport_pop()
    obs.gs_set_render_target(prev_render_target, prev_zstencil_target)

    obs.obs_leave_graphics()
end

function draw_cursor(data, mouse_pos)
    obs.obs_enter_graphics()

    local prev_render_target = obs.gs_get_render_target()
    local prev_zstencil_target = obs.gs_get_zstencil_target()

    obs.gs_set_render_target(data.ui_texture, nil)
    obs.gs_viewport_push()
    obs.gs_set_viewport(0, 0, data.width, data.height)
    obs.gs_projection_push()
    obs.gs_ortho(0, data.width, 0, data.height, 0.0, 1.0)

    obs.gs_blend_state_push()
    obs.gs_reset_blend_state()
    
    -- Set the color being used (or set the eraser).
    local solid = obs.obs_get_base_effect(obs.OBS_EFFECT_SOLID)
    local color = obs.gs_effect_get_param_by_name(solid, "color")
    local tech  = obs.gs_effect_get_technique(solid, "Solid")

    local size = draw_size
    local color_v4 = obs.vec4()

    if color_index == 0 then
        obs.vec4_from_rgba(color_v4, 0xff000000)
        obs.gs_effect_set_vec4(color, color_v4)
        size = eraser_size
    else
        obs.vec4_from_rgba(color_v4, color_array[color_index])
        obs.gs_effect_set_vec4(color, color_v4)
    end

    obs.gs_technique_begin(tech)
    obs.gs_technique_begin_pass(tech, 0)

    -- Perform matrix transformations for the dot at the
    -- start of the line (start cap).
    obs.gs_matrix_push()
    obs.gs_matrix_identity()
    obs.gs_matrix_translate3f(mouse_pos.x, mouse_pos.y, 0)

    obs.gs_matrix_push()
    obs.gs_matrix_scale3f(size, size, 1.0)
    
    -- Draw start of line.
    if color_index == 0 then
        obs.gs_load_vertexbuffer(eraser_vert)
        obs.gs_draw(obs.GS_LINESTRIP, 0, 0)
    else
        obs.gs_load_vertexbuffer(dot_vert)
        obs.gs_draw(obs.GS_TRIS, 0, 0)
    end

    obs.gs_matrix_pop()
    obs.gs_matrix_pop()

    -- Done drawing line, restore everything.
    obs.gs_technique_end_pass(tech)
    obs.gs_technique_end(tech)

    obs.gs_blend_state_pop()

    obs.gs_projection_pop()
    obs.gs_viewport_pop()
    obs.gs_set_render_target(prev_render_target, prev_zstencil_target)

    obs.obs_leave_graphics()
end

-- Check whether current foreground window is relevant to us.
function window_match(window_name)
    
    local valid_names = {}
    
    -- If studio mode is enabled, only allow drawing on main
    -- window (Program). If non-studio mode, allow drawing on
    -- the (Preview) window, instead.
    if obs.obs_frontend_preview_program_mode_active() then
        table.insert(valid_names, "(Program)")
    else
        table.insert(valid_names, "(Preview)")
    end
    
    -- Always allow drawing on projection of the scene containing
    -- the active whiteboard.
    if scene_name then
        table.insert(valid_names, scene_name)
    end

    -- Check that the currently selected projector matches one
    -- of the ones listed above.
    for name_index = 1, #valid_names do
        local valid_name = valid_names[name_index]
        local window_name_suffix = string.sub(window_name, -string.len(valid_name) - 1)
        if window_name_suffix == (" " .. valid_name) then
            return true
        end
    end

    return false
end

function update_vertices()
    obs.obs_enter_graphics()
    
    -- LINE VERTICES
    -- Create vertices for line of given width (user-defined 'draw_size').
    -- These vertices are for two triangles that make up each line.
    if line_vert then
        obs.gs_vertexbuffer_destroy(line_vert)
    end

    obs.gs_render_start(true)
    obs.gs_vertex2f(0, 0)
    obs.gs_vertex2f(1, 0)
    obs.gs_vertex2f(0, 2)
    obs.gs_vertex2f(0, 2)
    obs.gs_vertex2f(1, 2)
    obs.gs_vertex2f(1, 0)
    
    line_vert = obs.gs_render_save()
    
    -- DOT VERTICES
    -- Create vertices for a dot (filled circle) of specified width,
    -- which is used to round off the ends of the lines.
    if dot_vert then
        obs.gs_vertexbuffer_destroy(dot_vert)
    end
    
    obs.gs_render_start(true)

    local sectors = 100
    local angle_delta = (2 * math.pi) / sectors

    local circum_points = {}
    for i=0,(sectors-1) do
        table.insert(circum_points, {
            math.sin(angle_delta * i),
            math.cos(angle_delta * i)
        })
    end

    for i=0,(sectors-1) do
        local point_a = circum_points[i + 1]
        local point_b = circum_points[((i + 1) % sectors) + 1]
        obs.gs_vertex2f(0, 0)
        obs.gs_vertex2f(point_a[1], point_a[2])
        obs.gs_vertex2f(point_b[1], point_b[2])
    end

    dot_vert = obs.gs_render_save()

    -- ERASER CURSOR VERTICES
    -- Create vertices for a circle outline
    -- which is shown as the cursor when using the eraser

    if eraser_vert then
        obs.gs_vertexbuffer_destroy(eraser_vert)
    end
    
    obs.gs_render_start(true)

    local circum_points = {}
    for i=0,sectors do
        obs.gs_vertex2f(
            math.sin(angle_delta * i),
            math.cos(angle_delta * i)
        )
    end

    eraser_vert = obs.gs_render_save()
    
    obs.obs_leave_graphics()
end

function valid_position(cur_x, cur_y, width, height)
    -- If the mouse is within the boundaries of the screen, or was
    -- previously within the boundaries of the screen, it is a valid
    -- position to draw a line to.
    if (cur_x >= 0 and cur_x < width and cur_y >= 0 and cur_y < height) then
        return true
    end    
    return false
end

function clear(pressed)
    if not pressed or not is_drawable_window(winapi.GetForegroundWindow()) then
        return
    end

    clear_table(lines)
    needs_clear = true
end

function colorswap(pressed)
    if not pressed or not is_drawable_window(winapi.GetForegroundWindow()) then
        return
    end

    swap_color = true
end

function erasertoggle(pressed)
    if not pressed or not is_drawable_window(winapi.GetForegroundWindow()) then
        return
    end

    eraser = not eraser
end

function undo(pressed)
    if not pressed or not is_drawable_window(winapi.GetForegroundWindow()) then
        return
    end

    if #lines > 0 then
        table.remove(lines, #lines)
    end

    needs_clear = true
end

function clear_button()
    clear_table(lines)
    needs_clear = true
end

function clear_table(tab)
    for k, _ in pairs(tab) do tab[k] = nil end
end

function image_source_load(image, file)
    obs.obs_enter_graphics()
    obs.gs_image_file_free(image);
    obs.obs_leave_graphics()

    obs.gs_image_file_init(image, file);

    obs.obs_enter_graphics()
    obs.gs_image_file_init_texture(image);
    obs.obs_leave_graphics()

    if not image.loaded then
        print("failed to load texture " .. file);
    end
end

function create_textures(data)
    obs.obs_enter_graphics()
    
    if data.canvas_texture ~= nil then
        obs.gs_texture_destroy(data.canvas_texture)
    end

    data.canvas_texture = obs.gs_texture_create(data.width, data.height, obs.GS_RGBA, 1, nil, obs.GS_RENDER_TARGET)
    print("create canvas texture " .. data.width .. " " .. data.height)
    
    if data.ui_texture ~= nil then
        obs.gs_texture_destroy(data.ui_texture)
    end

    data.ui_texture = obs.gs_texture_create(data.width, data.height, obs.GS_RGBA, 1, nil, obs.GS_RENDER_TARGET)
    print("create ui texture " .. data.width .. " " .. data.height)

    obs.obs_leave_graphics()
end

-- Render our output to the screen.
source_def.video_render = function(data, effect)
    effect = obs.obs_get_base_effect(obs.OBS_EFFECT_DEFAULT)

    if effect and data.canvas_texture and data.ui_texture then
        obs.gs_blend_state_push()
        obs.gs_reset_blend_state()
        obs.gs_matrix_push()
        obs.gs_matrix_identity()

        obs.gs_blend_function(obs.GS_BLEND_ONE, obs.GS_BLEND_INVSRCALPHA)

        while obs.gs_effect_loop(effect, "Draw") do
            obs.obs_source_draw(data.canvas_texture, 0, 0, 0, 0, false);
            obs.obs_source_draw(data.ui_texture, 0, 0, 0, 0, false);
        end

        obs.gs_matrix_pop()
        obs.gs_blend_state_pop()
    end
end

source_def.get_width = function(data)
    return 1920
end

source_def.get_height = function(data)
    return 1080
end

-- When source is active, get the currently displayed scene's name and
-- set the active flag to true.
source_def.activate = function(data)
    local scene = obs.obs_frontend_get_current_scene()
    scene_name = obs.obs_source_get_name(scene)
    data.active = true
    obs.obs_source_release(scene)
end

source_def.deactivate = function(data)
    data.active = false
end

function script_properties()
    local properties = obs.obs_properties_create()    

    local eraser_toggle = obs.obs_properties_add_bool(properties, "eraser", "Eraser")
    
    obs.obs_properties_add_button(properties, "clear", "Clear Whiteboard", clear_button)
    
    return properties
end

function script_defaults(settings)
    obs.obs_data_set_default_bool(settings, "eraser", false)
    
    color_index = 1
    draw_size = 6
    eraser = false
end

function script_description()
    -- Using [==[ and ]==] as string delimiters, purely for IDE syntax parsing reasons.
    return [==[Adds a whiteboard.
    
Add this source on top of your scene, then project your entire scene and draw on the projector window. Each scene can have one whiteboard.
    
Hotkeys can be set to toggle color, draw_size, and eraser. An additional hotkey can be set to wipe the canvas.
    
The settings on this page will unfortunately not update in real-time when using hotkeys, due to limitations with OBS's script properties.]==]
end

function dump(o)
   if type(o) == 'table' then
      local s = '{ '
      for k,v in pairs(o) do
         if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. '['..k..'] = ' .. dump(v) .. ','
      end
      return s .. '} '
   else
      return tostring(o)
   end
end

obs.obs_register_source(source_def)
