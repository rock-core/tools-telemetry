require 'telemetry'

POLL_PERIOD = 1.0 # in seconds
Orocos.initialize

# start default tcp server on port 20001
server = Telemetry::Server.new

# report errors on the console
name_service = Orocos::Async::CORBA.name_service
name_service.on_error do |error|
    Vizkit.error error
end

# forward all tasks on the global name service
name_service.on_task_added do |name|
    puts "forward #{name}"
    server.forward(Orocos::Async.name_service.proxy(name),POLL_PERIOD)
end

# start eventloop
Orocos::Async.exec
