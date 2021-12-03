

mutable struct TinkerforgeConnection
  host::IPAddr = ip"127.0.0.1"
  port::Integer = 4223
  connection

  function TinkerforgeConnection()
    Conda.pip_interop(true)
    Conda.pip("install", "Tinkerforge")
    tinkerforge = pyimport("tinkerforge")
    ip_connection_package = pyimport("tinkerforge.ip_connection")
    ipcon = ip_connection_package.IPConnection()
    ipcon.connect("127.0.0.1", 4223)
    lcd_package = pyimport("tinkerforge.bricklet_lcd_20x4")
    lcd = lcd_package.BrickletLCD20x4("BL1", ip_con)
  end
end

self.ip_con = IPConnection()
            self.ip_con.connect(self.HOST, self.PORT)
