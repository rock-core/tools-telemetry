
module Telemetry
    class Server < Orocos::Async::ObjectBase
        attr_reader :io

        def initialize(io=TCP::Server.new(20001))
            @io = io
            @listeners = Hash.new
        end

        def write_msg(msg = Outgoing::Message.new)
            @io.write msg.serialize
        end

        def write_msg_nonblock(msg = Outgoing::Message.new)
            @io.write_nonblock msg.serialize
        end

        def write(obj,annotations={})
            write_msg(Outgoing::Message.new(obj,annotations))
        end

        def write_nonblock(obj,annotations={})
            write_msg_nonblock(Outgoing::Message.new(obj,annotations))
        end

        def forward(obj,period)
            if obj.respond_to?(:on_state_change)
                forward_task(obj,period)
            elsif obj.respond_to?(:on_data)
                forward_port(obj,period)
            elsif obj.respond_to?(:on_change)
                forward_property(obj,period)
            else
                raise "Do not know how to forward #{obj}"
            end
        end

        def forward_task(task,period)
            annotations = Hash.new
            annotations[:task_name] = task.name
            annotations[:period] = period
            listener1 = task.on_state_change() do |state|
                annotations[:type] = :state_change
                write_nonblock(state,annotations)
            end
            listener2 = task.on_error() do |error|
                annotations[:type] = :error
                write_nonblock(error,annotations)
            end
            listener3 = task.on_port_reachable() do |port_name|
                forward_port(task.port(port_name),period)
            end
            listener4 = task.on_port_unreachable() do |port_name|
                remove(task.port(port_name))
            end
            listener5 = task.on_property_reachable() do |property_name|
                forward_property(task.property(property_name),period)
            end
            listener6 = task.on_property_unreachable() do |property_name|
                remove(task.property(property_name))
            end
            @listeners[task] = [listener1,listener2,listener3,listener4,listener5,listener6]
        end

        def forward_port(port,period)
            annotations = Hash.new
            annotations[:task_name] = port.task.name
            annotations[:port_name] = port.name
            annotations[:period] = period
            listener = port.on_data(:period => period) do |data|
                annotations[:type_name] = port.type.name
                puts "write #{port.name}"
                write_nonblock(data,annotations)
            end
            @listeners[port] = listener
        end

        def forward_property(property,period)
            annotations = Hash.new
            annotations[:task_name] = property.task.name
            annotations[:property_name] = property.name
            annotations[:period] = period
            listener = property.on_change(:period => period) do |data|
                annotations[:type_name] = property.type.name
                write_nonblock(data,annotations)
            end
            @listeners[property] = listener
        end

        def forwarding?(obj)
            @listeners.has_key?(obj)
        end

        def remove(obj)
            Array(@listeners[obj]).map(&:stop)
            @listeners.delete(obj)
        end

        def connected?
        end

        def close
            @io.close
        end
    end
end
