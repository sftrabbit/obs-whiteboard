-- OBS Whiteboard Script
-- Authors: Mike Welsh (mwelsh@gmail.com), Tari, Joseph Mansfield
-- v1.3

obs = obslua

winapi = require("winapi")
require("winapi.cursor")
require("winapi.keyboard")
require("winapi.window")
require("winapi.winbase")

utils = require('utils')

local M = {}

function M.create_whiteboard()
    local whiteboard = {}

    whiteboard.needs_redraw = false
    whiteboard.swap_color = false
    whiteboard.toggle_size = false
    whiteboard.scene_name = nil

    whiteboard.previous_color_index = 1
    whiteboard.color_index = 1
    --Color format is 0xABGR
	-- OLD INDEX: RED, ORANGE, YELLOW, GREEN, TEAL, BLUE, INDIGO, PURPLE, MAGENTA
    -- whiteboard.color_array = {0xff4d4de8, 0xff4d9de8, 0xff4de5e8, 0xff4de88e, 0xff95e84d, 0xffe8d34d, 0xffe8574d, 0xffe84d9d, 0xffbc4de8}
	-- NEW INDEX: RED, ORANGE, YELLOW, GREEN (AVOCADO), BLUE, PURPLE, WHITE, GRAY, BLACK
    whiteboard.color_array = {0xff3a12ea, 0xff236cf5, 0xff0dc6ff, 0xff12b362, 0xfffc6541, 0xff80035e, 0xffffffff, 0xff808080, 0xff000000}
    whiteboard.draw_size = 6
    whiteboard.eraser_size = 26
    whiteboard.size_max = 12  -- size_max must be a minimum of 2.

    whiteboard.drawing = false
    whiteboard.arrow_mode = false
    whiteboard.lines = {}

    whiteboard.target_window = nil

    whiteboard.plus_pressed = false
    whiteboard.minus_pressed = false
    whiteboard.a_pressed = false
    whiteboard.backspace_pressed = false
    whiteboard.c_pressed = false
    whiteboard.e_pressed = false

    whiteboard.prev_mouse_pos = nil

    whiteboard.update_color = function()
        for i=1,#(whiteboard.color_array) do
            local key_down = winapi.GetAsyncKeyState(0x30 + i)
            if key_down and whiteboard.color_index ~= i then
                whiteboard.previous_color_index = whiteboard.color_index
                whiteboard.color_index = i
            end
        end

        local key_down = winapi.GetAsyncKeyState(0x30)
        if key_down then
            whiteboard.color_index = 0
            whiteboard.eraser_size = whiteboard.draw_size + 20
        end

        local key_down = winapi.GetAsyncKeyState(0x45)
        if key_down then
            if not whiteboard.e_pressed then
                if whiteboard.color_index == 0 then
                    whiteboard.color_index = whiteboard.previous_color_index
                else
                    whiteboard.previous_color_index = whiteboard.color_index
                    whiteboard.color_index = 0
                    whiteboard.eraser_size = whiteboard.draw_size + 20
                end

                whiteboard.e_pressed = true
            end
        else
            whiteboard.e_pressed = false
        end
    end

    whiteboard.update_size = function ()
        local plus_down = winapi.GetAsyncKeyState(winapi.VK_OEM_PLUS)
        if plus_down then
            if not whiteboard.plus_pressed then
                local eraser = whiteboard.color_index == 0

                if eraser and whiteboard.eraser_size < 100 then
                    whiteboard.eraser_size = whiteboard.eraser_size + 4
                elseif not eraser and whiteboard.draw_size < 100 then
                    whiteboard.draw_size = whiteboard.draw_size + 4
                end
                whiteboard.plus_pressed = true
            end
        else
            whiteboard.plus_pressed = false
        end

        local minus_down = winapi.GetAsyncKeyState(winapi.VK_OEM_MINUS)
        if minus_down then
            if not whiteboard.minus_pressed then
                local eraser = whiteboard.color_index == 0

                if eraser and whiteboard.eraser_size > 3 then
                    whiteboard.eraser_size = whiteboard.eraser_size - 4
                elseif not eraser and whiteboard.draw_size > 3 then
                    whiteboard.draw_size = whiteboard.draw_size - 4
                end
                whiteboard.minus_pressed = true
            end
        else
            whiteboard.minus_pressed = false
        end
    end

    whiteboard.update_mode = function ()
        local key_down = winapi.GetAsyncKeyState(0x41)
        if key_down then
            if not whiteboard.a_pressed then
                whiteboard.arrow_mode = not whiteboard.arrow_mode
                whiteboard.a_pressed = true
            end
        else
            whiteboard.a_pressed = false
        end
    end

    whiteboard.is_drawable_window = function (window)
        local window_name = winapi.InternalGetWindowText(window, nil)
        if not window_name then
            return false
        end

        return whiteboard.window_match(window_name) and
            (string.find(window_name, "Windowed Projector", 1, true) or
            string.find(window_name, "Fullscreen Projector", 1, true))
    end

    whiteboard.get_mouse_pos = function (data, window)
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

    -- Check whether current foreground window is relevant to us.
    whiteboard.window_match = function (window_name)
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
        if whiteboard.scene_name then
            table.insert(valid_names, whiteboard.scene_name)
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

    whiteboard.valid_position = function (cur_x, cur_y, width, height)
        -- If the mouse is within the boundaries of the screen, or was
        -- previously within the boundaries of the screen, it is a valid
        -- position to draw a line to.
        if (cur_x >= 0 and cur_x < width and cur_y >= 0 and cur_y < height) then
            return true
        end    
        return false
    end

    whiteboard.check_clear = function ()
        local key_down = winapi.GetAsyncKeyState(0x43)
        if key_down then
            if not whiteboard.c_pressed then
                utils.clear_table(whiteboard.lines)
                whiteboard.needs_redraw = true
                whiteboard.c_pressed = true
            end
        else
            whiteboard.c_pressed = false
        end
    end

    whiteboard.check_undo = function ()
        local key_down = winapi.GetAsyncKeyState(0x08)
        if key_down then
            if not whiteboard.backspace_pressed then
                if #(whiteboard.lines) > 0 then
                    table.remove(whiteboard.lines, #(whiteboard.lines))
                end

                whiteboard.needs_redraw = true
                whiteboard.backspace_pressed = true
            end
        else
            whiteboard.backspace_pressed = false
        end
    end

    whiteboard.update = function (source, graphics)
		local shift_down = winapi.GetAsyncKeyState(0x10)
		
        local mouse_down = winapi.GetAsyncKeyState(winapi.VK_LBUTTON)
        local window = winapi.GetForegroundWindow()
        if mouse_down then
            if whiteboard.is_drawable_window(window) then
                whiteboard.target_window = window
            else
                whiteboard.target_window = nil
            end
        end

        if not whiteboard.drawing and window == whiteboard.target_window then
            whiteboard.update_color()
            whiteboard.update_size()
            whiteboard.update_mode()
            whiteboard.check_undo()
            whiteboard.check_clear()
        end

        if mouse_down then
            if window and window == whiteboard.target_window then
                local mouse_pos = whiteboard.get_mouse_pos(source, window)

                local size = whiteboard.draw_size
                if whiteboard.color_index == 0 then
                    size = whiteboard.eraser_size
                end
                
                if whiteboard.color_index ~= 0 or #(whiteboard.lines) > 0 then
					if (not whiteboard.drawing and shift_down and #whiteboard.lines > 0) then
						-- Extend previous point
						whiteboard.drawing = true
                        local current_line = whiteboard.lines[#(whiteboard.lines)]
						local lastpoint = current_line.points[ #(current_line.points) ]
						
						whiteboard.prev_mouse_pos = {x = lastpoint.x, y = lastpoint.y}
					end
					
                    if whiteboard.drawing then
                        local effect = obs.obs_get_base_effect(obs.OBS_EFFECT_DEFAULT)
                        if not effect then
                            return
                        end
						
                        local new_segment = {
                            color = whiteboard.color_index,
                            size = size,
                            arrow = whiteboard.arrow_mode,
                            points = {
                                { x = whiteboard.prev_mouse_pos.x, y = whiteboard.prev_mouse_pos.y },
                                { x = mouse_pos.x, y = mouse_pos.y }
                            }
                        }

                        local current_line = whiteboard.lines[#(whiteboard.lines)]

                        table.insert(
                            current_line.points,
                            { x = mouse_pos.x, y = mouse_pos.y }
                        )

                        graphics.render_to_texture(graphics.canvas_texture, function()
                            graphics.draw_lines({ new_segment })
                        end)

                        if whiteboard.arrow_mode then
                            graphics.render_to_texture(graphics.ui_texture, function()
                                graphics.draw_arrow_head(current_line)
                            end)
                        end
                    else
                        if whiteboard.valid_position(mouse_pos.x, mouse_pos.y, source.width, source.height) then
                            table.insert(whiteboard.lines, {
                                color = whiteboard.color_index,
                                size = size,
                                arrow = whiteboard.arrow_mode,
                                points = {{ x = mouse_pos.x, y = mouse_pos.y }}
                            })
                            whiteboard.drawing = true
                        end
                    end
                end

                whiteboard.prev_mouse_pos = mouse_pos
            end
        end

        if window and window == whiteboard.target_window then
            local mouse_pos = whiteboard.get_mouse_pos(source, window)
            if whiteboard.valid_position(mouse_pos.x, mouse_pos.y, source.width, source.height) then
                graphics.render_to_texture(graphics.ui_texture, function()
                    graphics.draw_cursor(mouse_pos)
                end)
            end
        end

        if not mouse_down then
            if whiteboard.prev_mouse_pos then
                if #(whiteboard.lines) >= 1 and whiteboard.arrow_mode and whiteboard.color_index ~= 0 then
                    graphics.render_to_texture(graphics.canvas_texture, function()
                        graphics.draw_arrow_head(whiteboard.lines[#(whiteboard.lines)])
                    end)
                end

                whiteboard.prev_mouse_pos = nil
                whiteboard.drawing = false
            end
        end
    end

    return whiteboard
end

return M
