require 'websocket'

module Telemetry
    module TCP
        class Server < ::Orocos::Async::ObjectBase
            attr_accessor :timeout
            define_events :connected, :disconnected,:ip_disconnected,:port_disconnected,:port_connected

            def initialize(port)
                super(self.class.name,::Orocos::Async.event_loop)
                @timeout = 5.0
                @server = TCPServer.open(port)
                @server.setsockopt(:SOCKET, :REUSEADDR, true)
                @clients = Hash.new do |h,key|
                    h[key] = []
                end

                #wait for client connections
                p = Proc.new do |client,error|
                    event_loop.async_with_options(@server.method(:accept),{:sync_key => @server},&p) unless @server.closed?

                    # do not do handshake to prevent traffic to the robot
                    # which is not allowed by the spacebot rules !!!
                    if !error && client
                        @clients[client.remote_address.ip_address] << client
                        emit_connected client
                        emit_port_connected client.remote_address.ip_port
                    end
                end
                event_loop.async_with_options(@server.method(:accept),{:sync_key => @server},&p)

                on_disconnected do |client|
                    begin
                        @clients.each do |key,ports|
                            ports.delete(client)
                            emit_ip_disconnected key if ports.empty?
                        end
                        emit_port_disconnected client.remote_address.ip_port
                    rescue Errno::ENOTCONN
                    end
                end

                #watch dog
                event_loop.every(1) do
                    closed?
                end
            end

            def close
                @clients.each_value do |clients|
                    clients.each do |c|
                        emit_disconnected c
                    end
                end
                @server.close
            end

            def eof?
                @clients.each_pair do |key,sockets|
                    s = sockets.find do |s|
                        !event_loop.thread_pool.sync_keys.include?(s) && !s.eof?
                    end
                    return s if s
                end
            end

            def closed?
                @clients.each_pair do |key,sockets|
                    s = sockets.find do |s|
                        if !event_loop.thread_pool.sync_keys.include?(s) && s.closed?
                            emit_disconnected s
                        else
                            s
                        end
                    end
                    return false if s
                end
                true
            end

            def write(string)
                #write string to each ip address
                @clients.each_key do |key|
                    #find non busy socket
                    bytes = nil
                    time = Time.now
                    while !bytes
                        @clients[key].find do |s|
                            begin
                                next if event_loop.thread_pool.sync_keys.include?(s) 
                                if s.closed?
                                    event_loop.call do
                                        emit_disconnected s
                                    end
                                    next
                                end
                                bytes = event_loop.sync(s,s) do |s|
                                    # construct frame
                                    frame = WebSocket::Frame::Outgoing::Server.new(:data => string.to_s,:type => :binary)
                                    raise "WebSocket frame type is not supported by the selected draft!" unless frame.support_type?
                                    s.send(frame.to_s,0)
                                end
                            rescue Errno::EPIPE,Errno::ECONNRESET
                                event_loop.call do
                                    emit_disconnected s
                                end
                                next
                            end
                        end
                        unless bytes
                            Telemetry.warn "timeout"
                            return
                            raise "timeout" if(Time.now-time) > timeout
                            sleep 0.05
                        end
                    end
                    bytes
                end
            end

            def write_nonblock(string)
                #write string to each ip address
                @clients.each_pair do |key,sockets|
                    next if sockets.empty?
                    event_loop.async(self.method(:write),string) do |bytes,error|
                        # TODO do some error handling
                    end
                end
            end
        end
    end
end
