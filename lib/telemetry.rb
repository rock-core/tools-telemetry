require 'orocos/async'
require 'telemetry/message'
require 'telemetry/server'
require 'telemetry/client'
require 'telemetry/tcp'

require 'utilrb/logger'
module Telemetry
    extend Logger::Root('Telemetry', Logger::WARN)
end

