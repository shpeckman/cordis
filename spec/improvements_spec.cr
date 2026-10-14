# spec/improvements_spec.cr
require "./spec_helper"

class ImprovementService < Cordis::Service
  def initialize(ctx : Cordis::Context, name : String = "improvement")
    super(ctx, name)
  end
end

describe "Cordis improvements" do
  it "raises specific service errors" do
    ctx = Cordis::Context.new
    svc = ImprovementService.new(ctx)

    expect_raises(Cordis::DuplicateServiceError, "Service already registered") do
      ctx.reflect.provide("improvement", svc)
    end

    expect_raises(Cordis::ServiceNotProvidedError, "Cannot set property without provide") do
      ctx.reflect.set("missing", svc)
    end

    expect_raises(Cordis::ServiceNotInjectedError, "Service not injected: missing") do
      ctx.service("missing")
    end
  end

  it "exposes reflection and registry introspection" do
    ctx = Cordis::Context.new
    svc = ImprovementService.new(ctx)
    ctx.registry.plugin("plugin", svc)

    ctx.reflect.registered_names.should contain("improvement")
    ctx.reflect.active?("improvement").should be_true
    ctx.reflect.impl("improvement").should_not be_nil
    ctx.service_active?("improvement").should be_true
    ctx.service("improvement").should eq(svc)
    ctx.registry.names.should contain("plugin")
    ctx.registry.count.should eq(1)
  end

  it "supports once listeners and listener counts" do
    ctx   = Cordis::Context.new
    value = 0

    ctx.events.once("once_event") do |_args|
      value += 1
      nil
    end

    ctx.events.listener_count("once_event").should eq(1)
    ctx.events.emit("once_event")
    ctx.events.emit("once_event")
    value.should eq(1)
    ctx.events.listener_count("once_event").should eq(0)
  end

  it "supports typed event payloads" do
    ctx      = Cordis::Context.new
    received = ""

    handler = ->(payload : String) { received = payload; nil }
    typed = ctx.events.typed("typed_event", String)
    typed.on(&handler)
    typed.emit("payload")

    received.should eq("payload")
  end

  it "cancels cancellable hooks when parallel execution times out" do
    ctx       = Cordis::Context.new
    cancelled = Channel(Bool).new(1)

    ctx.events.on_cancellable("slow_parallel") do |_args, token|
      token.on_cancel do
        cancelled.send(true)
        nil
      end
      sleep 5.seconds
      nil
    end

    expect_raises(Cordis::AggregateHookError, /TimeoutError/) do
      ctx.events.parallel("slow_parallel", Array(Cordis::Any).new, 10.milliseconds)
    end

    select
    when cancelled.receive
    when timeout(1.second)
      fail "cancellable hook was not cancelled"
    end
  end

  it "rejects new async event work after shutdown" do
    ctx = Cordis::Context.new
    ctx.events.shutdown

    expect_raises(Cordis::DisposedError, "EventsService is shut down") do
      ctx.events.background("after_shutdown")
    end
  end

  it "marks nodes failed when an active effect raises" do
    ctx  = Cordis::Context.new
    node = Cordis::LifecycleNode.new(ctx)

    expect_raises(RuntimeError, "boom") do
      node.effect { raise RuntimeError.new("boom") }
    end

    node.failed?.should be_true
    node.last_error.should_not be_nil
  end

  it "tracks disposal reason and lifecycle introspection" do
    ctx  = Cordis::Context.new
    node = Cordis::LifecycleNode.new(ctx)
    node.active?.should be_true
    node.dependencies_met?.should be_true
    node.effect_count.should eq(0)

    node.dispose("test shutdown")
    node.disposed?.should be_true
    node.dispose_reason.should eq("test shutdown")

    expect_raises(Cordis::DisposedError) do
      node.effect { -> { nil } }
    end
  end

  it "reads logger level from intercepted configuration" do
    ctx   = Cordis::Context.new
    child = ctx.intercept("logger", "error".as(Cordis::Any))

    child.logger.level.should eq(Cordis::LoggerLevel::ERROR)
    ctx.logger.level.should eq(Cordis::LoggerLevel::DEBUG)
  end
end
