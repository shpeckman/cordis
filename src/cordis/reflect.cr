# src/cordis/reflect.cr
require "sync/shared"
require "random/secure"

module Cordis
  class ReflectService
    class Impl
      property name  : String
      property value : Injectable
      property node  : LifecycleNode

      def initialize(@name : String, @value : Injectable, @node : LifecycleNode)
      end
    end

    protected property store : Sync::Shared(Hash(String, Impl))

    def initialize(@ctx : Context, store : Sync::Shared(Hash(String, Impl))? = nil)
      @store = store || Sync::Shared(Hash(String, Impl)).new(Hash(String, Impl).new)
    end

    def get(name : String, strict : Bool = true) : Injectable?
      key = @ctx.resolve_isolate(name)
      return nil unless key

      @store.shared do |hash|
        impl = hash[key]?
        return nil unless impl
        return nil if strict && impl.node.state != LifecycleNode::State::ACTIVE
        impl.value
      end
    end

    def provide(name : String, value : Injectable) : Nil
      key             = @ctx.resolve_isolate(name)
      isolate_changed = false

      unless key
        key = "#{name}_#{Random::Secure.hex(4)}"
        @ctx.root.isolate[name] = key
        isolate_changed = true
      end

      impl = Impl.new(name, value, @ctx.node)

      @store.lock do |hash|
        if hash.has_key?(key)
          raise Errors::DuplicateService.new("Service already registered")
        end
        hash[key] = impl
      end

      @ctx.node.dispose_tasks.push(-> {
        @store.lock { |hash| hash.delete(key) }
        broadcast(name)
        nil
      })

      broadcast(name, isolate_changed)
    end

    def set(name : String, value : Injectable) : Nil
      key = @ctx.resolve_isolate(name)
      raise Errors::ServiceNotProvided.new("Cannot set property without provide") unless key

      @store.lock do |hash|
        impl = hash[key]?
        raise Errors::ServiceNotProvided.new("Cannot set property without provide") unless impl
        impl.value = value
      end

      broadcast(name)
    end

    def has?(name : String) : Bool
      !!impl(name)
    end

    def active?(name : String) : Bool
      !!get(name, strict: true)
    end

    def impl(name : String) : Impl?
      key = @ctx.resolve_isolate(name)
      return nil unless key
      @store.shared { |hash| hash[key]? }
    end

    def registered_names : Array(String)
      @store.shared { |hash| hash.values.map(&.name).uniq }
    end

    def keys : Array(String)
      @store.shared { |hash| hash.keys }
    end

    def each(&block : Proc(Impl, Nil)) : Nil
      @store.shared { |hash| hash.values.each { |impl| block.call(impl) } }
    end

    private def broadcast(name : String, isolate_changed : Bool = false) : Nil
      @ctx.root.events.background("internal/isolate") if isolate_changed
      @ctx.root.events.background("internal/update:#{name}")
      @ctx.root.events.background("internal/update")
    end
  end
end
