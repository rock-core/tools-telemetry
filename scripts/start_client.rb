require 'telemetry'
require 'vizkit'
#host = "10.250.3.30"
host = "192.168.56.102"

clients = []
0.upto 4 do
    clients << Telemetry::TCP::Client.new(host,20001)
end

client = Telemetry::Client.new(clients)
#client = Telemetry::Client.new 
inspector = Vizkit.default_loader.TaskInspector
inspector.add_name_service client.name_service_async
inspector.show

Vizkit.exec

