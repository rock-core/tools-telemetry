require 'telemetry/telemetry'
require 'telemetry/base'

# The toplevel namespace for telemetry
#
# You should describe the basic idea about telemetry here
require 'utilrb/logger'
module Telemetry
    extend Logger::Root('Telemetry', Logger::WARN)
end

