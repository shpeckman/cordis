# src/cordis/macros.cr
module Cordis
  macro define_service(name, type)
    class ::Cordis::Context
      def {{name.id}} : {{type.id}}
        result = self.reflect.get({{name.id.stringify}}, strict: true)
        if result.nil?
          raise ::Cordis::Errors::ServiceNotInjected.new("Service not injected or inactive: " + {{name.id.stringify}})
        end
        result.as({{type.id}})
      end

      def {{name.id}}? : {{type.id}}?
        result = self.reflect.get({{name.id.stringify}}, strict: true)
        result.as?({{type.id}})
      end
    end
  end
end
