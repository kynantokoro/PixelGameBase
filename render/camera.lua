--- Camera module to use in combination with the camera.go or camera.script

local const = require "main.constants"

local M = {}

M.MSG_ENABLE = hash("enable")
M.MSG_DISABLE = hash("disable")
M.MSG_UNFOLLOW = hash("unfollow")
M.MSG_FOLLOW = hash("follow")
M.MSG_FOLLOW_OFFSET = hash("follow_offset")
M.MSG_RECOIL = hash("recoil")
M.MSG_SHAKE = hash("shake")
M.MSG_SHAKE_COMPLETED = hash("shake_completed")
M.MSG_STOP_SHAKING = hash("stop_shaking")
M.MSG_DEADZONE = hash("deadzone")
M.MSG_UPDATE_CAMERA = hash("update_camera")
M.MSG_ZOOM_TO = hash("zoom_to")

local HIGH_DPI = (sys.get_config("display.high_dpi", "0") == "1")
local dpi_ratio = 1

M.SHAKE_BOTH = hash("both")
M.SHAKE_HORIZONTAL = hash("horizontal")
M.SHAKE_VERTICAL = hash("vertical")

local GAME_WIDTH = const.GAME_WIDTH or tonumber(sys.get_config("display.width")) or 960
local GAME_HEIGHT = const.GAME_HEIGHT or tonumber(sys.get_config("display.height")) or 640
local UPDATE_FREQUENCY = tonumber(sys.get_config("display.update_frequency") or sys.get_config("display.frame_cap"))
if UPDATE_FREQUENCY == 0 then UPDATE_FREQUENCY = 60 end

local WINDOW_WIDTH = GAME_WIDTH
local WINDOW_HEIGHT = GAME_HEIGHT

-- center camera to middle of screen
local OFFSET = vmath.vector3(GAME_WIDTH / 2, GAME_HEIGHT / 2, 0)

local VECTOR3_ZERO = vmath.vector3(0)
local VECTOR3_MINUS1_Z = vmath.vector3(0, 0, -1.0)
local VECTOR3_UP = vmath.vector3(0, 1.0, 0)

local MATRIX4 = vmath.matrix4()

local cameras = {}
local camera_ids = {}
-- track if the cameras list has changed or not
local cameras_dirty = true

-- setup a fixed aspect ratio projection with a fixed zoom
local function fixed_zoom_projection(camera_id, near_z, far_z, zoom)
	local camera = cameras[camera_id]
	local ww = camera.viewport and camera.viewport.z
	local wh = camera.viewport and camera.viewport.w

	local projected_width = ww / (zoom / dpi_ratio)
	local projected_height = wh / (zoom / dpi_ratio)
	local xoffset = -(projected_width - GAME_WIDTH) / 2
	local yoffset = -(projected_height - GAME_HEIGHT) / 2
	return vmath.matrix4_orthographic(xoffset, xoffset + projected_width, yoffset, yoffset + projected_height, near_z, far_z)
end

local function log(s, ...)
	if s then print(s:format(...)) end
end

local function check_game_object(id)
	local ok, err = pcall(go.get_position, id)
	return ok
end

-- http://www.rorydriscoll.com/2016/03/07/frame-rate-independent-damping-using-lerp/
-- return vmath.lerp(1 - math.pow(t, dt), v1, v2)
-- https://www.gamasutra.com/blogs/ScottLembcke/20180404/316046/Improved_Lerp_Smoothing.php
local function lerp_with_dt(t, dt, v1, v2)
	if dt == 0 then return vmath.lerp(t, v1, v2) end
	local rate = UPDATE_FREQUENCY * math.log10(1 - t)
	return vmath.lerp(1 - math.pow(10, rate * dt), v1, v2)
	--return vmath.lerp(t, v1, v2)
end

--- Set window scaling factor (basically retina or no retina screen)
-- There is no built-in way to detect if Defold is running on a retina or
-- non retina screen. This information combined with the High DPI setting
-- in game.project can be used to ensure that the zoom behaves the same way
-- regardless of screen type and High DPI setting.
-- You can use an extension such as DefOS to get the window scaling factor.
-- @param scaling_factor Scaling factor of the display (1=normal, 2=retina)
function M.set_window_scaling_factor(scaling_factor)
	assert(scaling_factor, "You must provide a scaling factor")
	if HIGH_DPI then
		dpi_ratio = 1 / scaling_factor
	else
		dpi_ratio = 1
	end
end

--- Update the window size
-- @param width Current window width
-- @param height Current window height
local function update_window_size()
	local width, height = window.get_size()
	if width == 0 or height == 0 then
		return
	end
	if width == WINDOW_WIDTH and height == WINDOW_HEIGHT then
		return
	end
	WINDOW_WIDTH = width
	WINDOW_HEIGHT = height
end

--- Get the window size
-- @return width Current window width
-- @return height Current window height
function M.get_window_size()
	return WINDOW_WIDTH, WINDOW_HEIGHT
end

--- Get the display size (ie from game.project)
-- @return width Display width from game.project
-- @return height Display height from game.project
function M.get_display_size()
	return GAME_WIDTH, GAME_HEIGHT
end

local function calculate_projection(camera)
	return fixed_zoom_projection(camera.id, camera.near_z, camera.far_z, camera.zoom)
end

local function calculate_view(camera, camera_world_pos, offset)
	local rot = go.get_world_rotation(camera.id)
	local pos = camera_world_pos - vmath.rotate(rot, OFFSET)
	if offset then
		pos = pos + offset
	end

	local look_at = pos + vmath.rotate(rot, VECTOR3_MINUS1_Z)
	local up = vmath.rotate(rot, VECTOR3_UP)
	local view = vmath.matrix4_look_at(pos, look_at, up)
	return view
end

local function refresh_cameras()
	if cameras_dirty then
		cameras_dirty = false
		local enabled_cameras = {}
		for camera_id,camera in pairs(cameras) do
			if camera.enabled then
				enabled_cameras[#enabled_cameras + 1] = camera
			end
		end
		table.sort(enabled_cameras, function(a, b)
			return b.order > a.order
		end)
		if #enabled_cameras ~= #camera_ids then
			camera_ids = {}
		end
		for i=1,#enabled_cameras do
			camera_ids[i] = enabled_cameras[i].id
		end
	end
end

--- Initialize a camera
-- Note: This is called automatically from the init() function of the camera.script
-- @param camera_id
-- @param camera_script_url
function M.init(camera_id, camera_script_url, settings)
	assert(camera_id, "You must provide a camera id")
	assert(camera_script_url, "You must provide a camera script url")
	cameras[camera_id] = settings
	cameras_dirty = true
	local camera = cameras[camera_id]
	camera.id = camera_id
	camera.url = camera_script_url
	camera.near_z = go.get(camera_script_url, "near_z")
	camera.far_z = go.get(camera_script_url, "far_z")
	camera.view = calculate_view(camera, go.get_world_position(camera_id))
	camera.viewport = vmath.vector4(0, 0, GAME_WIDTH, GAME_HEIGHT)
	camera.projection = calculate_projection(camera)

	if not sys.get_engine_info().is_debug then
		log = function() end
	end
end

--- Finalize a camera
-- Note: This is called automatically from the final() function of the camera.script
-- @param camera_id
function M.final(camera_id)
	assert(camera_id, "You must provide a camera id")
	-- check that a new camera with the same id but from a different go hasn't been
	-- replacing the camera that is being unregistered
	-- if this is the case we simply ignore the call to final()
	if cameras[camera_id].url == msg.url() then
		cameras[camera_id] = nil
		cameras_dirty = true
	end
end

--- Update a camera
-- When calling this function a number of things happen:
-- * Follow target game object (if any)
-- * Shake the camera (if enabled)
-- * Recalculate the view and projection matrix
--
-- Note: This is called automatically from the camera.script
-- @param camera_id
-- @param dt
function M.update(camera_id, dt)
	assert(camera_id, "You must provide a camera id")
	local camera = cameras[camera_id]
	if not camera then
		return
	end

	local enabled = go.get(camera.url, "enabled")
	local order = go.get(camera.url, "order")
	cameras_dirty = cameras_dirty or (camera.enabled ~= enabled)
	cameras_dirty = cameras_dirty or (camera.order ~= order)
	camera.enabled = enabled
	camera.order = order
	if not enabled then
		return
	end

	update_window_size()

	local camera_world_pos = go.get_world_position(camera_id)
	local camera_world_to_local_diff = camera_world_pos - go.get_position(camera_id)
	local follow_enabled = go.get(camera.url, "follow")
	if follow_enabled then
		local follow = go.get(camera.url, "follow_target")
		if not check_game_object(follow) then
			log("Camera '%s' has a follow target '%s' that does not exist", tostring(camera_id), tostring(follow))
		else
			local follow_horizontal = go.get(camera.url, "follow_horizontal")
			local follow_vertical = go.get(camera.url, "follow_vertical")
			local follow_offset = go.get(camera.url, "follow_offset")
			local target_world_pos = go.get_world_position(follow) + follow_offset
			local new_pos
			local deadzone_top = go.get(camera.url, "deadzone_top")
			local deadzone_left = go.get(camera.url, "deadzone_left")
			local deadzone_right = go.get(camera.url, "deadzone_right")
			local deadzone_bottom = go.get(camera.url, "deadzone_bottom")
			if deadzone_top ~= 0 or deadzone_left ~= 0 or deadzone_right ~= 0 or deadzone_bottom ~= 0 then
				new_pos = vmath.vector3(camera_world_pos)
				local left_edge = camera_world_pos.x - deadzone_left
				local right_edge = camera_world_pos.x + deadzone_right
				local top_edge = camera_world_pos.y + deadzone_top
				local bottom_edge = camera_world_pos.y - deadzone_bottom
				if target_world_pos.x < left_edge then
					new_pos.x = new_pos.x - (left_edge - target_world_pos.x)
				elseif target_world_pos.x > right_edge then
					new_pos.x = new_pos.x + (target_world_pos.x - right_edge)
				end
				if target_world_pos.y > top_edge then
					new_pos.y = new_pos.y + (target_world_pos.y - top_edge)
				elseif target_world_pos.y < bottom_edge then
					new_pos.y = new_pos.y - (bottom_edge - target_world_pos.y)
				end
			else
				new_pos = target_world_pos
			end
			new_pos.z = camera_world_pos.z
			if not follow_vertical then
				new_pos.y = camera_world_pos.y
			end
			if not follow_horizontal then
				new_pos.x = camera_world_pos.x
			end
			local follow_lerp = go.get(camera.url, "follow_lerp")
			camera_world_pos = lerp_with_dt(follow_lerp, dt, camera_world_pos, new_pos)
			camera_world_pos.z = new_pos.z
		end
	end

	go.set_position(camera_world_pos + camera_world_to_local_diff, camera_id)

	if camera.shake then
		camera.shake.duration = camera.shake.duration - dt
		if camera.shake.duration < 0 then
			if camera.shake.cb then camera.shake.cb() end
			camera.shake = nil
		else
			if camera.shake.horizontal then
				camera.shake.offset.x = (GAME_WIDTH * camera.shake.intensity) * (math.random() - 0.5)
			end
			if camera.shake.vertical then
				camera.shake.offset.y = (GAME_WIDTH * camera.shake.intensity) * (math.random() - 0.5)
			end
		end
	end

	if camera.recoil then
		camera.recoil.time_left = camera.recoil.time_left - dt
		if camera.recoil.time_left < 0 then
			camera.recoil = nil
		else
			local t = camera.recoil.time_left / camera.recoil.duration
			camera.recoil.offset = vmath.lerp(t, VECTOR3_ZERO, camera.recoil.offset)
		end
	end

	local offset
	if camera.shake or camera.recoil then
		offset = VECTOR3_ZERO
		if camera.shake then
			offset = offset + camera.shake.offset
		end
		if camera.recoil then
			offset = offset + camera.recoil.offset
		end
	end
	camera.offset = offset

	camera.near_z = go.get(camera.url, "near_z")
	camera.far_z = go.get(camera.url, "far_z")
	camera.zoom = go.get(camera.url, "zoom")
	camera.view = calculate_view(camera, camera_world_pos, offset)
	camera.projection = calculate_projection(camera)

	refresh_cameras()
end

--- Get list of camera ids
-- @return List of camera ids
function M.get_cameras()
	refresh_cameras()
	return camera_ids
end

--- Follow a game object
-- @param camera_id or nil for the first camera
-- @param target The game object to follow
-- @param options Table with options
--		lerp - lerp to smoothly move the camera towards the target (default: nil)
-- 		offset - Offset from target position (default: nil)
--		horizontal - true if following target along horizontal axis (default: true)
--		vertical - true if following target along vertical axis (default: true)
--		immediate - true if camera should be immediately positioned on the target
function M.follow(camera_id, target, options)
	camera_id = camera_id or camera_ids[1]
	assert(camera_id, "You must provide a camera id")
	assert(target, "You must provide a target")
	local lerp = options and options.lerp
	local offset = options and options.offset
	local horizontal = options and options.horizontal
	local vertical = options and options.vertical
	local immediate = options and options.immediate
	if horizontal == nil then horizontal = true end
	if vertical == nil then vertical = true end

	msg.post(cameras[camera_id].url, M.MSG_FOLLOW, {
		target = target,
		lerp = lerp,
		offset = offset,
		horizontal = horizontal,
		vertical = vertical,
		immediate = immediate,
	})
end

--- Unfollow a game object
-- @param camera_id or nil for the first camera
function M.unfollow(camera_id)
	camera_id = camera_id or camera_ids[1]
	assert(camera_id, "You must provide a camera id")
	msg.post(cameras[camera_id].url, M.MSG_UNFOLLOW)
end

--- Change the camera follow offset
-- @param camera_id or nil for the first camera
-- @param offset - Offset from target position
function M.follow_offset(camera_id, offset)
	camera_id = camera_id or camera_ids[1]
	assert(camera_id, "You must provide a camera id")
	assert(offset, "You must provide an offset")
	msg.post(cameras[camera_id].url, M.MSG_FOLLOW_OFFSET, { offset = offset })
end

--- Set the camera deadzone
-- @param camera_id or nil for the first camera
-- @param left Left edge of deadzone. Pass nil to remove deadzone.
-- @param top
-- @param right
-- @param bottom
function M.deadzone(camera_id, left, top, right, bottom)
	camera_id = camera_id or camera_ids[1]
	assert(camera_id, "You must provide a camera id")
	local camera = cameras[camera_id]
	if left and right and top and bottom then
		msg.post(camera.url, M.MSG_DEADZONE, { left = left, top = top, right = right, bottom = bottom })
	else
		msg.post(camera.url, M.MSG_DEADZONE)
	end
end

--- Shake a camera
-- @param camera_id or nil for the first camera
-- @param intensity Intensity of the shake in percent of screen width. Optional, default: 0.05.
-- @param duration Duration of the shake. Optional, default: 0.5s.
-- @param direction both|horizontal|vertical. Optional, default: both
-- @param cb Function to call when shake has completed. Optional
function M.shake(camera_id, intensity, duration, direction, cb)
	camera_id = camera_id or camera_ids[1]
	assert(camera_id, "You must provide a camera id")
	cameras[camera_id].shake = {
		intensity = intensity or 0.05,
		duration = duration or 0.5,
		horizontal = direction ~= M.SHAKE_VERTICAL or false,
		vertical = direction ~= M.SHAKE_HORIZONTAL or false,
		offset = vmath.vector3(0),
		cb = cb,
	}
end

--- Stop shaking a camera
-- @param camera_id or nil for the first camera
function M.stop_shaking(camera_id)
	camera_id = camera_id or camera_ids[1]
	assert(camera_id, "You must provide a camera id")
	cameras[camera_id].shake = nil
end

--- Simulate a recoil effect
-- @param camera_id or nil for the first camera
-- @param offset Amount to offset the camera with
-- @param duration Duration of the recoil. Optional, default: 0.5s.
function M.recoil(camera_id, offset, duration)
	camera_id = camera_id or camera_ids[1]
	assert(camera_id, "You must provide a strength id")
	cameras[camera_id].recoil = {
		offset = offset,
		duration = duration or 0.5,
		time_left = duration or 0.5,
	}
end

--- Set the zoom level of a camera
-- @param camera_id or nil for the first camera
-- @param zoom The zoom level of the camera
function M.set_zoom(camera_id, zoom)
	camera_id = camera_id or camera_ids[1]
	assert(camera_id, "You must provide a camera id")
	assert(zoom, "You must provide a zoom level")
	local camera = cameras[camera_id]
	msg.post(camera.url, M.MSG_ZOOM_TO, { zoom = zoom })
	camera.zoom = zoom
	camera.projection = calculate_projection(camera)
end

--- Get the zoom level of a camera
-- @param camera_id or nil for the first camera
-- @return Current zoom level of the camera
function M.get_zoom(camera_id)
	camera_id = camera_id or camera_ids[1]
	assert(camera_id, "You must provide a camera id")
	return cameras[camera_id].zoom
end

--- Get the projection matrix for a camera
-- @param camera_id or nil for the first camera
-- @return Projection matrix
function M.get_projection(camera_id)
	camera_id = camera_id or camera_ids[1]
	assert(camera_id, "You must provide a camera id")
	return cameras[camera_id].projection
end

--- Get the view matrix for a specific camera, based on the camera position
-- and rotation
-- @param camera_id or nil for the first camera
-- @return View matrix
function M.get_view(camera_id)
	camera_id = camera_id or camera_ids[1]
	assert(camera_id, "You must provide a camera id")
	return cameras[camera_id].view
end

--- Get the offset for a specific camera
-- @param camera_id or nil for the first camera
-- @return Offset (vector3)
function M.get_offset(camera_id)
	camera_id = camera_id or camera_ids[1]
	assert(camera_id, "You must provide a camera id")
	return cameras[camera_id].offset
end

--- Send the view and projection matrix for a camera to the render script
-- @param camera_id
function M.send_view_projection(camera_id)
	assert(camera_id, "You must provide a camera id")
	local camera = cameras[camera_id]
	local view = camera.view or MATRIX4
	local projection = camera.projection or MATRIX4
	msg.post("@render:", "set_view_projection", { id = camera_id, view = view, projection = projection })
end

return M
