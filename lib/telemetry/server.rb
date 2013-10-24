
module Telemetry
    class Server < Orocos::Async::ObjectBase
        attr_reader :io
        FORCE_REFRESH_PERIOD = 10.0 # in seconds - this is also used as keep alive signal
        WATCHDOG_PERIOD = 1.0 # in seconds

        ObjectInfo = Struct.new(:id,:listeners,:last_refresh)

        def initialize(io=TCP::Server.new(20001))
            super(self.class.name,Orocos::Async.event_loop)
            @io = io
            @objects = Hash.new

            event_loop.every WATCHDOG_PERIOD do
                @objects.each_pair do |key,val|
                    if(Time.now-val.last_refresh > FORCE_REFRESH_PERIOD)
                        Array(val.listeners).each do |listener|
                            next if !listener || !listener.last_args
                            listener.call *listener.last_args
                        end
                    end
                end
            end

            annotations = {:type => :error}
            event_loop.on_error(Exception) do |e|
                write_nonblock(0,e,annotations) do |bytes,error|
                end
            end
        end

        def write_msg(id,msg = Outgoing::Message.new)
            @io.write id,msg.serialize
        end

        def write_msg_nonblock(id,msg = Outgoing::Message.new,&block)
            @io.write_nonblock id,msg.serialize,&block
        end

        def write(id,obj,annotations={})
            write_msg(id,Outgoing::Message.new(obj,annotations))
        end

        def write_nonblock(id,obj,annotations={},&block)
            write_msg_nonblock(id,Outgoing::Message.new(obj,annotations),&block)
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
                next unless task.reachable?
                annotations[:type] = :task_state
                write_nonblock(@objects[task].id,state,annotations)
                @objects[task].last_refresh = Time.now
            end
            listener2 = task.on_error() do |error|
                # retransmit errors
                annotations[:type] = :error
                write_nonblock(@objects[task].id,error,annotations)
                @objects[task].last_refresh = Time.now
            end
            listener3 = task.on_port_reachable() do |port_name|
                forward_port(task.port(port_name,:period => period),period)
                @objects[task].last_refresh = Time.now
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
            listener7 = task.on_unreachable() do
                annotations[:type] = :unreachable
                write_nonblock(0,nil,annotations)
            end
            @objects[task] = ObjectInfo.new(@objects.size,[listener1,listener2],Time.now)
        end

        def forward_port(port,period)
            annotations = Hash.new
            annotations[:task_name] = port.task.name
            annotations[:port_name] = port.name
            annotations[:period] = period

            port.once_on_reachable do
                # ignore input ports
                next if port.respond_to?(:input?) && port.input?
                Telemetry.info "forwarding #{port.full_name}"
                listener = port.on_raw_data(:period => period) do |data|
                    next unless port.reachable? # this is needed because of watchdog
                    annotations[:type_name] = port.type_name
                    write_nonblock(@objects[port].id,data,annotations) do |bytes,error|
                        obj = @objects[port]
                        obj.last_refresh = Time.now if obj
                    end
                end
                @objects[port] = ObjectInfo.new(@objects.size,listener,Time.now)
            end
        end

        def forward_property(property,period)
            annotations = Hash.new
            annotations[:task_name] = property.task.name
            annotations[:property_name] = property.name
            annotations[:period] = period

            Telemetry.info "forwarding #{property.full_name}"
            listener = property.on_raw_change(:period => period) do |data|
                annotations[:type_name] = property.type_name
                next unless property.reachable? # this is needed because of watchdog
                write_nonblock(@objects[property].id,data,annotations) do |bytes,error|
                    obj = @objects[property]
                    obj.last_refresh = Time.now if obj
                end
            end
            @objects[property] = ObjectInfo.new(@objects.size,listener,Time.now)
        end

        def forwarding?(obj)
            @objects.has_key?(obj)
        end

        def remove(obj)
            return unless @objects[obj]
            Array(@objects[obj].listeners).map(&:stop)
            @objects.delete(obj)
        end

        def close
            @io.close
        end
    end
end
