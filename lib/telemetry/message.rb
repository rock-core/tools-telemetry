require 'yaml'
require 'base64'

module Telemetry
    # Telemetry base message
    class MessageBase
        attr_accessor :data
        attr_accessor :annotations

        def serialize
            to_yaml
        end
    end

    module Incoming
        class Message < MessageBase
            def initialize(str)
                message = YAML.load(str)
                @annotations = message.annotations
                @data = if @annotations[:type] == :typelib
                            begin
                                Orocos.load_typekit_for @annotations[:type_name],false
				if @annotations[:type_name] == "/transformer/TransformerStatus" || @annotations[:type_name] == "/aggregator/StreamAlignerStatus"
				   @annotations = Hash.new
                                   nil
				else
                                   data = Base64.decode64(message.data)
                                   Orocos.registry.get(@annotations[:type_name]).wrap(data)
                                end
                            rescue Orocos::TypekitTypeNotFound => e
                                e
                            end
                        else
                            message.data
                        end
            end
        end
    end

    module Outgoing
        class Message < MessageBase
            def initialize(obj,annotations={})
                @annotations = annotations
                @data = obj
            end

            def serialize
                msg = MessageBase.new
                msg.data = if data.is_a?(::Typelib::Type)
                               annotations[:type] ||= :typelib
                               annotations[:type_name] ||= data.class.name
                               Base64.encode64(data.to_byte_array)
                           else
                               data.to_s
                           end
                msg.annotations = annotations
                msg.serialize
            end
        end
    end
end
