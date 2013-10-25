# restarts the client every n seconds to stress the server

require 'telemetry'
require 'vizkit'

host = "10.250.3.30"
port = "20001"
#host = "192.168.56.102"

Orocos.initialize


while true
    # add multiple connections
    Orocos.warn "start client"
    clients = []
    0.upto 15 do
        clients << Telemetry::TCP::Client.new(host,port)
    end
    client = Telemetry::Client.new(clients)

    # proxy all task as corba tasks
    client.name_service_async.on_task_added do |task_name|
        task = client.name_service_async.proxy(task_name)
        puts "got task #{task_name}"
    end

    t = Time.now
    while Time.now-t < 20
        Orocos::Async.step
        sleep 0.001
    end
    Orocos.warn "stop client"
end
