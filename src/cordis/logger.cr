# src/cordis/logger.cr
require "log"

module Cordis
  enum LoggerLevel
    ERROR = 0
    WARN  = 1
    INFO  = 2
    DEBUG = 3
  end

  class LoggerService
    def initialize(@ctx : Context)
    end

    def level : LoggerLevel
      configured_level || LoggerLevel::DEBUG
    end

    def error(msg : String) : Nil
      return unless enabled?(LoggerLevel::ERROR)
      Log.error { msg }
    end

    def warn(msg : String) : Nil
      return unless enabled?(LoggerLevel::WARN)
      Log.warn { msg }
    end

    def info(msg : String) : Nil
      return unless enabled?(LoggerLevel::INFO)
      Log.info { msg }
    end

    def debug(msg : String) : Nil
      return unless enabled?(LoggerLevel::DEBUG)
      Log.debug { msg }
    end

    private def enabled?(required : LoggerLevel) : Bool
      level.value >= required.value
    end

    private def configured_level : LoggerLevel?
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

    private def parse_level(value : String) : LoggerLevel?
      case value.downcase
      when "error"
        LoggerLevel::ERROR
      when "warn", "warning"
        LoggerLevel::WARN
      when "info"
        LoggerLevel::INFO
      when "debug"
        LoggerLevel::DEBUG
      else
        nil
      end
    end
  end
end
