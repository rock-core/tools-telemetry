require 'telemetry/test'

MiniTest::Unit.autorun
describe Telemetry::Server do
    include Telemetry::SelfTest

    before do
        if !Orocos.initialized?
            Orocos.initialize
            Orocos.load_typekit 'base'
        end
        port = 10000 + rand(10000)
        @server = Telemetry::Server.new(Telemetry::TCP::Server.new(port))
        @client = Telemetry::Client.new(Telemetry::TCP::Client.new("localhost",port))
    end

    after do
        @server.close if @server
        @client.close if @client
    end

    describe "write" do
        it "should write a typelib obj" do
            t = Types::Base::Samples::LaserScan.new
            t.time = Time.now
            t.apply_changes_from_converted_types

            Orocos::Async.steps
            @server.write t
            obj=nil
            @client.on_data do |data,annotations|
                obj = data
            end
            Orocos::Async.steps

            assert(obj)
            assert_equal t.time.to_s,obj.time.to_s
            assert_equal t.class.name,obj.class.name
        end
    end

    describe "write_nonblock" do
        it "should write a typelib obj in a nonblocking manner" do
            t = Types::Base::Samples::LaserScan.new
            t.time = Time.now
            t.apply_changes_from_converted_types

            Orocos::Async.steps
            @server.write_nonblock t
            obj=nil
            @client.on_data do |data,annotations|
                obj = data
            end
            Orocos::Async.steps

            assert(obj)
            assert_equal t.time.to_s,obj.time.to_s
            assert_equal t.class.name,obj.class.name
            Orocos::Async.steps
        end
    end

    describe "forward_port" do
        it "should forward a orocos async port" do

            task = Orocos::RubyTaskContext.new("test_ports")
            port = task.create_output_port("laser_scan",Types::Base::Samples::LaserScan)

            aport = Orocos::Async.get("test_ports").port("laser_scan")
            aport.wait
            @server.forward_port(aport,0.1)

            # data must be emitted by the client
            sample=nil
            @client.on_data do |data,annotations|
                sample = data
            end

            #data must also be forwarded to the replay framework
            log_task = @client.name_service_async.proxy("test_ports")
            sample2 = nil
            log_task.port("laser_scan").on_data do |data|
                sample2 = data
            end

            # write samples to the task and check that both sinks are receiving
            # the data
            t = Types::Base::Samples::LaserScan.new
            port.write t
            Orocos::Async.steps
            3.times do
                # write data
                t.time = Time.now
                t.apply_changes_from_converted_types
                port.write t
                Orocos::Async.steps
                Orocos::Async.steps

                #check receiving
                assert(sample)
                assert_equal t.time.to_s,sample.time.to_s
                assert_equal t.class.name,sample.class.name
                assert(sample2)
                assert_equal t.time.to_s,sample2.time.to_s
                assert_equal t.class.name,sample2.class.name
            end

        end
    end

    describe "forward_property" do
        it "should forward a orocos async property" do

            task = Orocos::RubyTaskContext.new("test_property")
            prop = task.create_property("laser",Types::Base::Samples::LaserScan)
            prop.write prop.new_sample.zero!

            t = Orocos::Async.get("test_property")
            aprop = Orocos::Async.get("test_property").property("laser")
            aprop.wait
            @server.forward_property(aprop,0.1)

            # data must be emitted by the client
            sample=nil
            @client.on_data do |data,annotations|
                sample = data
            end

            #data must also be forwarded to the replay framework
            log_task = @client.name_service_async.proxy("test_property")
            log_task.wait
            sample2 = nil
            log_task.property("laser").on_change do |data|
                sample2 = data
            end

            # write samples to the task and check that both sinks are receiving
            # the data
            t = Types::Base::Samples::LaserScan.new
            Orocos::Async.steps
            3.times do
                # write data
                t.time = Time.now
                t.apply_changes_from_converted_types
                prop.write t
                Orocos::Async.steps
                Orocos::Async.steps

                #check receiving
                assert(sample)
                assert_equal t.time.to_s,sample.time.to_s
                assert_equal t.class.name,sample.class.name
                assert(sample2)
                assert_equal t.time.to_s,sample2.time.to_s
                assert_equal t.class.name,sample2.class.name
            end
        end
    end

    describe "forward_task" do
        it "should forward a orocos task" do

            task = Orocos::RubyTaskContext.new("test_task")
            port = task.create_output_port("laser_scan",Types::Base::Samples::LaserScan)
            prop = task.create_property("laser_prop",Types::Base::Samples::LaserScan)
            prop.write prop.new_sample.zero!

            t = Orocos::Async.get("test_task")
            @server.forward_task(t,0.1)

            reachable = nil
            port_reachable = nil
            property_reachable = nil
            state = nil
            sample1 = nil
            sample2 = nil
            log_task = @client.name_service_async.proxy("test_task",:period => 0.01)
            log_task.wait
            log_task.on_reachable do
                reachable = true
            end
            log_task.on_port_reachable do |name|
                port_reachable = name
            end
            log_task.on_property_reachable do |name|
                property_reachable = name
            end
            log_task.on_state_change do |state|
                state = state;
            end
            log_task.port("laser_scan").on_data do |data|
                sample1 = data
            end
            log_task.property("laser_prop").on_change do |data|
                sample2 = data
            end

            # write samples to the task and check that both sinks are receiving
            # the data
            t = Types::Base::Samples::LaserScan.new
            Orocos::Async.steps

            # write data
            t.time = Time.now
            t.apply_changes_from_converted_types
            prop.write t
            port.write t
            Orocos::Async.steps
            # we have to write twice
            port.write t
            Orocos::Async.steps

            #check receiving
            assert(reachable)
            assert_equal("laser_scan",port_reachable)
            assert_equal("laser_prop",property_reachable)
            puts state

            assert(sample1)
            assert_equal t.time.to_s,sample1.time.to_s
            assert_equal t.class.name,sample1.class.name
            assert(sample2)
            assert_equal t.time.to_s,sample2.time.to_s
            assert_equal t.class.name,sample2.class.name
        end
    end
end
