require 'telemetry'
require 'orocos/log'
require 'vizkit'

Orocos.initialize
server = Telemetry::Server.new

name_service = Orocos::Async::CORBA.name_service
name_service.on_task_added do |task_name|
end
name_service.on_error do |error|
    Vizkit.error error
end
#Orocos::Async.event_loop.on_error(Orocos::CORBA::ComError) do |e|
#    Vizkit.error e
#end

Orocos::Async.name_service.on_task_added do |name|
    puts "forward #{name}"
    server.forward(Orocos::Async.name_service.proxy(name),1.0)
end

#Orocos::Async.name_service.on_task_removed do |name|
#    puts "remove #{name}"
#    server.remove(Orocos::Async.name_service.proxy(name))
#end

Orocos::Async.exec


