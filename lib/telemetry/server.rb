
module Telemetry
    class Server < Orocos::Async::ObjectBase
        attr_reader :io
        FORCE_REFRESH_PERIOD = 10.0 # in seconds - this is also used as keep alive signal
        WATCHDOG_PERIOD = 1.0 # in seconds

        def initialize(io=TCP::Server.new(20001))
            super(self.class.name,Orocos::Async.event_loop)
            @io = io
            @last_refresh = Hash.new
            @objects = Hash.new
            event_loop.every WATCHDOG_PERIOD do
                @last_refresh.each_pair do |key,val|
                    if(Time.now-val > FORCE_REFRESH_PERIOD)
                        Array(@objects[key]).each do |listener|
                            next if !listener || !listener.last_args
                            listener.call *listener.last_args
                        end
                    end
                end
            end
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
                annotations[:type] = :task_state
                write_nonblock(state,annotations)
                @last_refresh[task] = Time.now
            end
            listener2 = task.on_error() do |error|
                annotations[:type] = :error
                write_nonblock(error,annotations)
                @last_refresh[task] = Time.now
            end
            listener3 = task.on_port_reachable() do |port_name|
                forward_port(task.port(port_name,:period => period),period)
                @last_refresh[task] = Time.now
            end
            listener4 = task.on_port_unreachable() do |port_name|
                remove(task.port(port_name))
                @last_refresh[task] = Time.now
            end
            listener5 = task.on_property_reachable() do |property_name|
                forward_property(task.property(property_name),period)
                @last_refresh[task] = Time.now
            end
            listener6 = task.on_property_unreachable() do |property_name|
                remove(task.property(property_name))
                @last_refresh[task] = Time.now
            end
            @objects[task] = [listener1,listener2]
            @last_refresh[task] = Time.now
        end

        def forward_port(port,period)
            annotations = Hash.new
            annotations[:task_name] = port.task.name
            annotations[:port_name] = port.name
            annotations[:period] = period

            # ignore input ports
            port.once_on_reachable do
                next if port.respond_to?(:input?) && port.input?
                puts "listener #{port.full_name}"
                @objects[port] = port.on_raw_data(:period => period) do |data|
                    annotations[:type_name] = port.type_name
                    write_nonblock(data,annotations)
                    @last_refresh[port] = Time.now
                end
                @last_refresh[port] = Time.now
            end
        end

        def forward_property(property,period)
            annotations = Hash.new
            annotations[:task_name] = property.task.name
            annotations[:property_name] = property.name
            annotations[:period] = period
            listener = property.on_raw_change(:period => period) do |data|
                annotations[:type_name] = property.type_name
                write_nonblock(data,annotations)
                @last_refresh[property] = Time.now
            end
            @objects[property] = listener
            @last_refresh[property] = Time.now
        end

        def forwarding?(obj)
            @objects.has_key?(obj)
        end

        def remove(obj)
            Array(@objects[obj]).map(&:stop)
            @objects.delete(obj)
            @last_refresh.delete(obj)
        end

        def connected?
        end

        def close
            @io.close
        end
    end
end
