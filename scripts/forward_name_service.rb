require 'telemetry'
require 'orocos/log'
require 'vizkit'

Orocos.initialize
server = Telemetry::Server.new

Orocos::Async.name_service.on_task_added do |name|
    puts "forward #{name}"
    server.forward(Orocos::Async.name_service.proxy(name),1.0)
end

Orocos::Async.name_service.on_task_removed do |name|
    puts "remove #{name}"
    server.remove(Orocos::Async.name_service.proxy(name))
end

Vizkit.exec


