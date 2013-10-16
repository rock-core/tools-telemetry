require 'telemetry'
require 'vizkit'

client = Telemetry::Client.new [Telemetry::TCP::Client.new("localhost",20001),
                                Telemetry::TCP::Client.new("localhost",20001),
                                Telemetry::TCP::Client.new("localhost",20001),
                                Telemetry::TCP::Client.new("localhost",20001),
                                Telemetry::TCP::Client.new("localhost",20001),
                                Telemetry::TCP::Client.new("localhost",20001),
                                Telemetry::TCP::Client.new("localhost",20001)]
inspector = Vizkit.default_loader.TaskInspector
inspector.add_name_service client.name_service_async
inspector.show

camera = client.name_service_async.proxy("camera")
camera.on_port_reachable do |bla|
    puts bla
end
#camera.port("frame_raw").on_data do |bla|
#    puts bla
#end

Vizkit.exec

