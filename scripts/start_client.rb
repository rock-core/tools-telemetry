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

Vizkit.exec

