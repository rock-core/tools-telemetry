require 'websocket'

module Telemetry
    module TCP
        class Server < ::Orocos::Async::ObjectBase
            TIME_TO_LIVE = 0.1   # message is removed if transmission has not started after n seconds

            define_events :connected, :disconnected,:ip_disconnected,:port_disconnected,:port_connected
            def initialize(port)
                super(self.class.name,::Orocos::Async.event_loop)
                @server = TCPServer.open(port)
                @server.setsockopt(:SOCKET, :REUSEADDR, true)
                @server.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY,false)
                @clients = Hash.new do |h,key|
                    h[key] = []
                end

                #wait for client connections
                p = Proc.new do |client,error|
                    event_loop.async_with_options(@server.method(:accept),{:sync_key => @server},&p) unless @server.closed?

                    # do not do handshake to prevent traffic to the robot
                    # which is not allowed by the spacebot rules !!!
                    if !error && client
                        client.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, false)
                        @clients[client.remote_address.ip_address] << client
                        emit_connected client
                        emit_port_connected client.remote_address.ip_port
                    else
                        Telemetry.error error
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
                    rescue Errno::ENOTCONN,IOError
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

            def write(id,string)
                frame = WebSocket::Frame::Outgoing::Server.new(:data => string.to_s,:type => :binary)
                raise "WebSocket frame type is not supported by the selected draft!" unless frame.support_type?
                msg = frame.to_s

                #write string to each ip address
                total_bytes = 0
                @clients.each_pair do |key,client|
                    next if client.empty?

                    # select socket
                    id_temp = id%(client.size)
                    s = client[id_temp]
                    bytes = msg.size

                    # get unique access to the socket
                    event_loop.sync_timeout(s,TIME_TO_LIVE) do
                        # send hole message
                        while bytes != 0
                            begin
                                b = s.syswrite(msg[msg.size-bytes..-1])
                                bytes -= b
                                total_bytes += b
                            rescue Errno::EBADF,Errno::EPIPE,Errno::ECONNRESET,IOError => e
                                Telemetry.warn "error on io: #{e}"
                                s.close unless s.closed?
                            rescue Errno::EAGAIN
                                Telemetry.warn "try again"
                                sleep 0.1
                                next
                            end
                            if s.closed?
                                event_loop.call do
                                    emit_disconnected s
                                end
                                break
                            end
                        end
                    end
                end
                total_bytes
            end

            def write_nonblock(id,string,&block)
                #write string to each ip address
                event_loop.async_with_options(self.method(:write),{:known_errors=>[Timeout::Error]},id,string) do |bok,error|
                    block.call(bok,error) if block_given?
                end
            end
        end
    end
end
