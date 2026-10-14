# src/cordis/lifecycle_node.cr
module Cordis
  class LifecycleNode
    enum State
      PENDING
      LOADING
      ACTIVE
      FAILED
      DISPOSED
      UNLOADING
      SUSPENDED
    end

    class Effect
      property name     : String?
      property block    : Proc(Disposable)
      property teardown : Disposable?
      property untrack  : Proc(Bool)?

      def initialize(@block : Proc(Disposable), @name : String? = nil)
      end
    end

    property uid             : Int32?
    property ctx             : Context
    property state           : State
    property inject          : Array(String)
    property dispose_tasks   : DisposableList
    property last_error      : Exception?
    property dispose_reason  : String?
    property last_transition : Time

    @effects             = Array(Effect).new
    @disposables         = DisposableList.new
    @dependency_untracks = Array(Disposable).new

    def initialize(parent : Context, is_root : Bool = false, inject : Array(String) = Array(String).new)
      @uid                 = 1
      @effects             = Array(Effect).new
      @disposables         = DisposableList.new
      @dispose_tasks       = DisposableList.new
      @inject              = inject.dup
      @dependency_untracks = Array(Disposable).new
      @last_error          = nil
      @dispose_reason      = nil
      @last_transition     = Time.utc

      if is_root
        @ctx   = parent
        @state = State::ACTIVE
      else
        @ctx   = parent.extend_context
        @state = State::PENDING
        @ctx.node = self
        refresh_subscriptions
        update_state
      end
    end

    def add_inject(deps : Array(String)) : Nil
      @inject.concat(deps).uniq!
      refresh_subscriptions
      update_state
    end

    def retry : Nil
      return if @state == State::DISPOSED || @state == State::UNLOADING
      @last_error = nil
      transition_to(State::PENDING)
      update_state
    end

    def effect(name : String? = nil, &block : -> Disposable) : Disposable
      if @state == State::DISPOSED || @state == State::UNLOADING
        raise Errors::Disposed.new("Cannot add effect to #{@state.to_s.downcase} lifecycle node")
      end

      record = Effect.new(block, name)
      @effects << record

      if @state == State::ACTIVE
        begin
          activate_record(record)
        rescue ex
          fail_from_effect(ex)
          raise ex
        end
      end

      -> {
        @effects.delete(record)
        if (u_proc = record.untrack) && (t_proc = record.teardown)
          if u_proc.call
            begin
              t_proc.call
            rescue ex
              @last_error = ex
            end
          end
        end
        record.untrack = nil
        record.teardown = nil
        nil
      }
    end

    def update_state : Nil
      return if @state == State::DISPOSED || @state == State::UNLOADING

      all_met = dependencies_met?

      if all_met && (@state == State::PENDING || @state == State::SUSPENDED)
        transition_to(State::LOADING)
        begin
          @effects.each { |record| activate_record(record) }
          transition_to(State::ACTIVE)
        rescue ex
          teardown_errors = clear_effect_teardowns
          error           = teardown_errors.empty? ? ex : Errors::AggregateHook.new([ex] + teardown_errors)
          transition_to(State::FAILED, error)
        end
        emit_update
      elsif !all_met && (@state == State::ACTIVE || @state == State::LOADING || @state == State::FAILED)
        transition_to(State::UNLOADING)
        errors = clear_effect_teardowns
        if errors.empty?
          transition_to(State::SUSPENDED)
        else
          transition_to(State::FAILED, Errors::AggregateHook.new(errors))
        end
        emit_update
      end
    end

    def dispose(reason : String = "disposed") : Nil
      return if @state == State::DISPOSED
      transition_to(State::UNLOADING)
      @dispose_reason = reason
      @dependency_untracks.each &.call
      @dependency_untracks.clear

      errors = clear_effect_teardowns
      @effects.clear
      @dispose_tasks.clear.each do |task|
        begin
          task.call
        rescue ex
          errors << ex
        end
      end

      @last_error = Errors::AggregateHook.new(errors) unless errors.empty?
      transition_to(State::DISPOSED)
      emit_update
    end

    def dispose_async(reason : String = "disposed") : Nil
      @ctx.execution_context.spawn do
        dispose(reason)
      end
    end

    def dependencies_met? : Bool
      @inject.each do |dep|
        return false if @ctx.reflect.get(dep, strict: true).nil?
      end
      true
    end

    def pending? : Bool
      @state == State::PENDING
    end

    def loading? : Bool
      @state == State::LOADING
    end

    def active? : Bool
      @state == State::ACTIVE
    end

    def suspended? : Bool
      @state == State::SUSPENDED
    end

    def failed? : Bool
      @state == State::FAILED
    end

    def disposed? : Bool
      @state == State::DISPOSED
    end

    def unloading? : Bool
      @state == State::UNLOADING
    end

    def effect_count : Int32
      @effects.size
    end

    def disposable_count : Int32
      @disposables.size
    end

    private def refresh_subscriptions : Nil
      @dependency_untracks.each &.call
      @dependency_untracks.clear
      return if @ctx.root.same?(@ctx) && @state == State::ACTIVE

      @inject.each do |dep|
        @dependency_untracks << @ctx.root.events.on("internal/update:#{dep}") do |_args|
          update_state
          nil
        end
      end
      @dependency_untracks << @ctx.root.events.on("internal/isolate") do |_args|
        update_state
        nil
      end
      @dependency_untracks << @ctx.root.events.on("internal/update") do |_args|
        update_state
        nil
      end
    end

    private def activate_record(record : Effect) : Nil
      return if record.teardown
      eff_proc = record.block.call
      record.teardown = eff_proc
      record.untrack = @disposables.push(eff_proc)
    end

    private def clear_effect_teardowns : Array(Exception)
      errors = Array(Exception).new
      @disposables.clear.each do |teardown|
        begin
          teardown.call
        rescue ex
          errors << ex
        end
      end
      @effects.each do |record|
        record.teardown = nil
        record.untrack = nil
      end
      errors
    end

    private def fail_from_effect(ex : Exception) : Nil
      errors      = clear_effect_teardowns
      @last_error = errors.empty? ? ex : Errors::AggregateHook.new([ex] + errors)
      transition_to(State::FAILED, @last_error)
      emit_update
    end

    private def transition_to(state : State, error : Exception? = nil) : Nil
      @state           = state
      @last_transition = Time.utc
      @last_error      = error if error
      @ctx.root.events.background("lifecycle/#{state.to_s.downcase}", [state.to_s.as(Any)]) rescue nil
    end

    private def emit_update : Nil
      @ctx.root.events.background("internal/update") rescue nil
    end
  end
end
