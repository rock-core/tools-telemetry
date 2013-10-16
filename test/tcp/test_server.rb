require 'telemetry/test'

MiniTest::Unit.autorun
describe Telemetry::TCP::Server do
    include Telemetry::SelfTest

    before do
    end
    after do
    end

    describe "write" do
        it "should write data on the given tcp port" do
            server = Telemetry::TCP::Server.new(20001)
            client = Telemetry::TCP::Client.new("localhost",20001)
            Orocos::Async.steps
            message = "Test123"
            server.write message
            Orocos::Async.steps
            assert_equal(message,client.gets)
        end
    end
end
