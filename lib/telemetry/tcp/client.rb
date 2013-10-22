require 'websocket'

module Telemetry
    module TCP
        class Client
            def initialize(host,port,client_port=nil)
                @host = host
                @port = port
                @socket = nil
            end

            # blocking call waits until a full frame was received
            def gets()
                connect
                while @socket && !@socket.closed?
                    data = begin
                               @socket.recv(10240)
                           rescue Errno::ECONNRESET
                           end
                    if !data || data.empty?
                        close
                        connect
                        next
                    end
                    @frame << data
                    f = @frame.next
                    return f.to_s if f
                end
            end

            def closed?
                if !@socket || @socket.closed?
                    true
                else
                    false
                end
            end

            def close
                @socket.close unless closed?
                @socket = nil
            end

            def connect
                while !@socket
                    begin
                        reset
                    rescue Errno::ECONNREFUSED,Errno::ECONNRESET
                        @socket = nil
                        Vizkit.warn "#{self}: connection refused to #{@host}:#{@port}. Trying again in 1 second"
                        sleep 1
                    end
                end
            end

            def reset
                close
                @socket = TCPSocket.open(@host,@port)
                @frame = WebSocket::Frame::Incoming::Server.new()
            end
        end
    end
end
