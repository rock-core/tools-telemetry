
module Telemetry
    class Client < Orocos::Async::ObjectBase
        WATCHDOG_PERIOD = 1.0  # in seconds
        SERVER_TIMEOUT = 120.0  # in seconds

        class Stream
            attr_accessor :name
            attr_accessor :type
            attr_accessor :typename
            attr_accessor :size
            attr_accessor :metadata 
            def initialize(name,type,metadata={})
                @type = type
                @name = name
                @metadata = metadata
                @typename = type.class.name
                @size = 1
            end
        end

        class DummyReplay
            attr_reader :last_sample_pos
            attr_reader :first_sample_pos
            attr_reader :aligned

            def initialize
                @first_sample_pos = 0
                @last_sample_pos = 0
                @aligned = false
            end

            def aligned?
                @aligned
            end
        end

        attr_reader :ios
        attr_reader :name_service
        attr_reader :name_service_async
        define_events :data                 # |data,annotations|

        def initialize(*ios)
            super(self.class.name,::Orocos::Async.event_loop)
            ios << TCP::Client.new("localhost",20001) if ios.empty?
            @ios = ios.flatten
            @dummy_replay = DummyReplay.new
            @name_service_async = Orocos::Async::Local::NameService.new
            @name_service = Orocos::Local::NameService.new
            @name_service.name = "Telemetry"
            @name_service_async.name = "Telemetry"
            @last_alive = nil

            @ios.each do |io|
                p = Proc.new do |str,error|
                    @last_alive = Time.now
                    if error
                        puts error
                        io.close unless io.closed?
                    end
                    msg = begin
                              Incoming::Message.new(str) if str
                          rescue ArgumentError => e
                              Vizkit.warn e
                              nil
                          rescue Exception => e
                              puts e.class
                              io.close
                              puts "message broken puts #{str[0..100].inspect}"
                              Vizkit.error e
                              nil
                          end
                    event_loop.async_with_options(io.method(:gets),{:sync_key => io,:known_errors =>[IOError,Errno::EBADF]},&p)
                    next unless msg
                    emit_data(msg.data,msg.annotations)

                    if msg.annotations.has_key?(:port_name)
                        port_msg(msg)
                    elsif msg.annotations.has_key?(:property_name)
                        property_msg(msg)
                    elsif msg.annotations.has_key?(:type) && msg.annotations[:type] == :task_state
                        task = task_msg(msg)
                        task.current_state = msg.data
                    elsif msg.annotations.has_key?(:type) && msg.annotations[:type] == :task_unreachable
                        task = task_msg(msg)
                        task.current_state = :Unreachable
                    elsif msg.annotations.has_key?(:type) && msg.annotations[:type] == :error
                        Telemetry.warn "Server Eventloop: #{msg.data}"
                        if msg.annotations.has_key?(:task_name)
                            task = task_msg(msg)
                            task.current_state=msg.data.to_s
                        end
                    end
                end
                event_loop.async_with_options(io.method(:gets),{:sync_key => io,:known_errors =>[IOError,Errno::EBADF,RuntimeError]},&p)
            end
            event_loop.every(WATCHDOG_PERIOD) do
                io = @ios.find do |io|
                    !io.closed?
                end
                if !io
                    @name_service.each_task do |task|
                        task.current_state = :TIMEOUT
                    end
                elsif @last_alive && Time.now - @last_alive > SERVER_TIMEOUT
                    @last_alive = nil
                    @ios.map &:close
                    @name_service.each_task do |task|
                        task.current_state = :TIMEOUT
                    end
                end
            end
        end

        def task_msg(msg)
            name = msg.annotations[:task_name]
            raise "task has no name" if !name || name.empty?
            task = if @name_service.names.include? name
                       @name_service.get(name)
                   else
                       t = Orocos::Log::TaskContext.new(@dummy_replay,name,"Telemetry","")
                       t.current_state = :REACHABLE
                       @name_service.register t
                       @name_service_async.register t
                       t
                   end
            task
        end

        def port_msg(msg)
            if msg.data.is_a?(Exception)
                Vizkit.warn "error on port #{msg.annotations[:task_name]}.#{msg.annotations[:port_name]}:#{msg.data}"
                return
            end
            task = task_msg(msg)
            port_name = msg.annotations[:port_name]
            raise "port has no name" if !port_name || port_name.empty?
            if !task.has_port?(port_name)
                stream = Stream.new("#{task.name}.#{port_name}",msg.data.class)
                task.add_port("Telemetry",stream).tracked = true
            end
            port = task.port(port_name)
            port.write(msg.data)
            port
        end

        def property_msg(msg)
            if msg.data.is_a?(Exception)
                Vizkit.warn "error on property #{msg.annotations[:task_name]}.#{msg.annotations[:port_name]}:#{msg.data}"
                return
            end
            task = task_msg(msg)
            prop_name = msg.annotations[:property_name]
            raise "property has no name" if !prop_name|| prop_name.empty?
            if !task.has_property?(prop_name)
                stream = Stream.new("#{task.name}.#{prop_name}",msg.data.class,{"rock_stream_type" => "property"})
                task.add_property("Telemetry",stream).tracked = true
            end
            prop = task.property(prop_name)
            prop.write(msg.data)
            prop
        end

        def close
            @ios.map(&:close)
        end
    end
end
