require 'websocket'
require 'thread'

module Telemetry
    module TCP
        class Client
            def initialize(host,port,client_port=nil)
                @host = host
                @port = port
                @socket = nil
                @mutex = Mutex.new
            end

            # blocking call waits until a full frame was received
            def gets()
                connect
                @mutex.synchronize do
                    f = @frame.next
                    return f.to_s if f
                    while !@socket.closed?
                        data = begin
                                   @socket.recv(640000)
                               rescue Errno::ECONNRESET => e
                                   Telemetry.warn "close socket because of: #{e}"
                                   close
                                   return
                               end
                        if !data || data.empty?
                            Telemetry.warn "close socket: empty data package"
                            close
                            return
                        end
                        @frame << data
                        f = @frame.next
                        return f.to_s if f
                    end
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
            end

            def connect
                while !@socket || @socket.closed?
                    begin
                        reset
                    rescue Errno::ECONNREFUSED,Errno::ECONNRESET,Errno::ECONNABORTED
                        Vizkit.warn "#{self}: connection refused to #{@host}:#{@port}. Trying again in 1 second"
                        sleep 1
                    rescue Errno::EHOSTUNREACH
                        Vizkit.warn "#{self}: no route to #{@host}:#{@port}. Trying again in 1 second"
                        sleep 1
                    end
                end
            end

            def reset
                close
                @mutex.synchronize do
                    @socket = TCPSocket.open(@host,@port)
                    @frame = WebSocket::Frame::Incoming::Server.new()
                end
            end
        end
    end
end
