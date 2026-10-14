# src/cordis/errors.cr
module Cordis
  module Errors
    class Error < Exception
    end

    class ServiceNotFound < Error
    end

    class ServiceNotInjected < Error
    end

    class DuplicateService < Error
    end

    class ServiceNotProvided < Error
    end

    class DependencyTimeout < Error
    end

    class AggregateHook < Error
      getter errors : Array(Exception)

      def initialize(@errors : Array(Exception))
        super("AggregateError: #{errors.map(&.message).join(", ")}")
      end
    end

    class Lifecycle < Error
    end

    class Disposed < Lifecycle
    end
  end
end
