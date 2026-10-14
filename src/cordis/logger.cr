# src/cordis/logger.cr
require "log"

module Cordis
  class LoggerService
    enum Level
      ERROR = 0
      WARN  = 1
      INFO  = 2
      DEBUG = 3
    end

    def initialize(@ctx : Context)
    end

    def level : Level
      configured_level || Level::DEBUG
    end

    def error(msg : String) : Nil
      return unless enabled?(Level::ERROR)
      Log.error { msg }
    end

    def warn(msg : String) : Nil
      return unless enabled?(Level::WARN)
      Log.warn { msg }
    end

    def info(msg : String) : Nil
      return unless enabled?(Level::INFO)
      Log.info { msg }
    end

    def debug(msg : String) : Nil
      return unless enabled?(Level::DEBUG)
      Log.debug { msg }
    end

    private def enabled?(required : Level) : Bool
      level.value >= required.value
    end

    private def configured_level : Level?
      case value = @ctx.resolve_intercept("logger")
      when String
        parse_level(value)
      when Hash(String, String)
        value["level"]?.try { |level| parse_level(level) }
      when MessagePack::Any
        begin
          raw = value["level"]?
          raw ? parse_level(raw.as_s) : nil
        rescue
          nil
        end
      else
        nil
      end
    end

    private def parse_level(value : String) : Level?
      case value.downcase
      when "error"
        Level::ERROR
      when "warn", "warning"
        Level::WARN
      when "info"
        Level::INFO
      when "debug"
        Level::DEBUG
      else
        nil
      end
    end
  end
end
