# src/cordis/events.cr
require "sync/shared"
require "sync/mutex"

class Cordis::EventsService
  alias Hook = Proc(Array(Any), Any)
  alias CancellableHook = Proc(Array(Any), CancellationToken, Any)

  class HookEntry
    getter hook             : Hook?
    getter cancellable_hook : CancellableHook?

    def initialize(@hook : Hook? = nil, @cancellable_hook : CancellableHook? = nil)
    end

    def call(args : Array(Any), token : CancellationToken) : Any
      if cancellable = @cancellable_hook
        cancellable.call(args, token)
      elsif normal = @hook
        normal.call(args)
      else
        nil
      end
    end
  end

  class TypedEvent(T)
    def initialize(@events : EventsService, @name : String)
    end

    def on(&block : Proc(T, Nil)) : Disposable
      wrapper = ->(args : Array(Any)) : Any {
        block.call(args[0].as(T))
        nil
      }
      @events.on(@name, &wrapper)
    end

    def emit(payload : T) : Nil
      @events.emit(@name, [payload.as(Any)])
    end
  end

  @hooks = Sync::Shared(Hash(String, Array(HookEntry))).new(Hash(String, Array(HookEntry)).new)

  @pending_mutex = Sync::Mutex.new
  @pending       = Hash(String, Int32).new
  @tokens        = Array(CancellationToken).new
  @shutdown      = false

  def initialize(@ctx : Context)
  end

  def on(name : String, &block : Hook) : Disposable
    entry = HookEntry.new(hook: block)
    @hooks.lock do |h|
      h[name] ||= Array(HookEntry).new
      h[name] << entry
    end
    -> {
      @hooks.lock do |h|
        h[name]?.try &.delete(entry)
      end
      nil
    }
  end

  def on_cancellable(name : String, &block : CancellableHook) : Disposable
    entry = HookEntry.new(cancellable_hook: block)
    @hooks.lock do |h|
      h[name] ||= Array(HookEntry).new
      h[name] << entry
    end
    -> {
      @hooks.lock do |h|
        h[name]?.try &.delete(entry)
      end
      nil
    }
  end

  def once(name : String, &block : Hook) : Disposable
    disposable = -> { nil }
    wrapper = ->(args : Array(Any)) : Any {
      result = block.call(args)
      disposable.call
      result
    }
    disposable = on(name, &wrapper)
    disposable
  end

  def typed(name : String, type : T.class) : TypedEvent(T) forall T
    TypedEvent(T).new(self, name)
  end

  def emit(name : String, args : Array(Any) = Array(Any).new) : Nil
    hooks = @hooks.shared { |h| h[name]? ? h[name].dup : nil }
    return unless hooks
    token = CancellationToken.new
    hooks.each { |entry| entry.call(args, token) }
  end

  def emit_typed(name : String, payload : T) : Nil forall T
    emit(name, [payload.as(Any)])
  end

  def background(name : String, args : Array(Any) = Array(Any).new) : Nil
    ensure_running!
    hooks = @hooks.shared { |h| h[name]? ? h[name].dup : nil }
    return unless hooks

    token = CancellationToken.new
    register_token(token)
    hooks.each do |entry|
      spawn_tracked(name) do
        begin
          entry.call(args, token)
        rescue ex
          @ctx.logger.error("Background execution error in hook '#{name}': #{ex.message}")
        end
      end
    end
    unregister_token(token)
  end

  def parallel(name : String, args : Array(Any) = Array(Any).new, max_wait : Time::Span = default_max_wait) : Nil
    ensure_running!
    hooks = @hooks.shared { |h| h[name]? ? h[name].dup : nil }
    return unless hooks

    channel = Channel(Exception | Nil).new(hooks.size)
    token   = CancellationToken.new
    register_token(token)

    hooks.each do |entry|
      spawn_tracked(name) do
        begin
          entry.call(args, token)
          channel.send(nil)
        rescue ex
          channel.send(ex)
        end
      end
    end

    errors = Array(Exception).new
    hooks.size.times do
      select
      when result = channel.receive
        errors << result if result.is_a?(Exception)
      when timeout(max_wait)
        token.cancel
        errors << Errors::DependencyTimeout.new("TimeoutError: Hook execution for '#{name}' exceeded timeout")
        break
      end
    end

    unregister_token(token)
    raise Errors::AggregateHook.new(errors) unless errors.empty?
  end

  def serial(name : String, args : Array(Any) = Array(Any).new, max_wait : Time::Span = default_max_wait) : Any
    ensure_running!
    hooks = @hooks.shared { |h| h[name]? ? h[name].dup : nil }
    return nil unless hooks

    channel = Channel(Any | Exception).new(1)
    token   = CancellationToken.new
    register_token(token)

    spawn_tracked(name) do
      begin
        val = nil
        hooks.each do |entry|
          break if token.cancelled?
          result = entry.call(args, token)
          unless result.nil?
            val = result
            break
          end
        end
        channel.send(val)
      rescue ex
        channel.send(ex)
      end
    end

    select
    when result = channel.receive
      unregister_token(token)
      if result.is_a?(Exception)
        raise result
      else
        return result
      end
    when timeout(max_wait)
      token.cancel
      unregister_token(token)
      raise Errors::DependencyTimeout.new("TimeoutError: Hook execution for '#{name}' exceeded timeout")
    end
  end

  def bail(name : String, args : Array(Any) = Array(Any).new, max_wait : Time::Span = default_max_wait) : Any
    serial(name, args, max_wait)
  end

  def listener_count(name : String) : Int32
    @hooks.shared { |h| h[name]? ? h[name].size : 0 }
  end

  def event_names : Array(String)
    @hooks.shared { |h| h.keys }
  end

  def shutdown? : Bool
    @pending_mutex.synchronize { @shutdown }
  end

  def shutdown(timeout : Time::Span = 10.seconds) : Nil
    tokens = @pending_mutex.synchronize do
      @shutdown = true
      @tokens.dup
    end
    tokens.each &.cancel

    deadline = Time.local + timeout
    while pending_total > 0 && Time.local < deadline
      sleep 1.millisecond
    end

    if pending_total > 0
      raise Errors::DependencyTimeout.new("TimeoutError: EventsService shutdown exceeded timeout")
    end
  end

  private def default_max_wait : Time::Span
    case value = @ctx.resolve_intercept("events")
    when Int32
      value.milliseconds
    when Int64
      value.milliseconds
    when Float64
      value.seconds
    when Hash(String, String)
      if ms = value["timeout_ms"]?.try &.to_i?
        ms.milliseconds
      elsif seconds = value["timeout_s"]?.try &.to_f?
        seconds.seconds
      else
        10.seconds
      end
    else
      10.seconds
    end
  end

  private def ensure_running! : Nil
    if shutdown?
      raise Errors::Disposed.new("EventsService is shut down")
    end
  end

  private def register_token(token : CancellationToken) : Nil
    @pending_mutex.synchronize { @tokens << token }
  end

  private def unregister_token(token : CancellationToken) : Nil
    @pending_mutex.synchronize { @tokens.delete(token) }
  end

  private def track(name : String) : Nil
    @pending_mutex.synchronize do
      @pending[name] = (@pending[name]? || 0) + 1
    end
  end

  private def untrack(name : String) : Nil
    @pending_mutex.synchronize do
      next unless count = @pending[name]?
      if count <= 1
        @pending.delete(name)
      else
        @pending[name] = count - 1
      end
    end
  end

  private def pending_total : Int32
    @pending_mutex.synchronize { @pending.values.sum }
  end

  private def spawn_tracked(name : String, &block : -> Nil) : Nil
    track(name)
    @ctx.execution_context.spawn do
      begin
        block.call
      ensure
        untrack(name)
      end
    end
  end
end
