require 'telemetry'
require 'vizkit'

#host = "10.250.3.30"
port = "20001"
host = "192.168.56.102"

Orocos.initialize

# add multiple connections
clients = []
0.upto 15 do
    clients << Telemetry::TCP::Client.new(host,port)
end
client = Telemetry::Client.new(clients)

# show task inspector for incoming traffic
inspector = Vizkit.default_loader.TaskInspector
inspector.add_name_service client.name_service_async

# proxy all task as corba tasks
client.name_service_async.on_task_added do |task_name|
    client.name_service_async.proxy(task_name).to_ruby
end

inspector.show
Vizkit.exec
