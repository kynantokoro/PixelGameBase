local Button = require "libs.crit.button"
local render_utils = require "render.utils"

local DefaultButton = {}

DefaultButton = setmetatable({}, {__index = Button})

function DefaultButton.new(node, self)
  self = self or {}

  self = Button.new(node, self)

  self.action_to_position = render_utils.action_to_gui_pick

  return self
end

return DefaultButton
