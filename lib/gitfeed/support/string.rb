# Some monkey patch to add colorized output in console
class String
  COLORS_CODE = {
    red: 31,
    green: 32,
    yellow: 33,
    blue: 34,
    pink: 35,
    light_blue: 36
  }.freeze

  # colorization
  def colorize(color_code)
    "\e[#{COLORS_CODE[color_code.to_sym]}m#{self}\e[0m"
  end

  def underline
    "\e[4m#{self}\e[0m"
  end

  def bold
    "\e[1m#{self}\e[0m"
  end
end
