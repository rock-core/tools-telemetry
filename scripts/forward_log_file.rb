require 'telemetry'
require 'orocos/log'
require 'vizkit'

log = Orocos::Log::Replay.open(ARGV)
log.track true

server = Telemetry::Server.new

log.tasks.each do |task|
    server.forward(task.to_proxy,1.0)
end

Vizkit.control log
Vizkit.exec


