# spec/events_spec.cr
require "./spec_helper"

describe Cordis::EventsService do
  it "registers and emits events" do
    ctx   = Cordis::Context.new
    value = 0

    ctx.events.on("increment") do |args|
      value += args[0].as(Int32)
      nil
    end

    ctx.events.emit("increment", [5.as(Cordis::Any)])
    value.should eq(5)
  end

  it "removes event listeners via disposable" do
    ctx   = Cordis::Context.new
    value = 0

    dispose = ctx.events.on("increment") do |args|
      value += args[0].as(Int32)
      nil
    end

    dispose.call
    ctx.events.emit("increment", [5.as(Cordis::Any)])
    value.should eq(0)
  end

  it "handles serial execution and returns early on truthy value" do
    ctx = Cordis::Context.new

    ctx.events.on("pipeline") { |args| nil }
    ctx.events.on("pipeline") { |args| args[0] }
    ctx.events.on("pipeline") { |args| 999.as(Cordis::Any) }

    result = ctx.events.serial("pipeline", [42.as(Cordis::Any)])
    result.should eq(42)
  end

  it "handles bail which delegates to serial" do
    ctx = Cordis::Context.new

    ctx.events.on("pipeline") { |args| args[0] }
    result = ctx.events.bail("pipeline", [42.as(Cordis::Any)])
    result.should eq(42)
  end

  it "handles parallel execution" do
    ctx   = Cordis::Context.new
    mutex = Sync::Mutex.new
    value = 0

    ctx.events.on("par") do |args|
      mutex.synchronize { value += 1 }
      nil
    end

    ctx.events.on("par") do |args|
      mutex.synchronize { value += 2 }
      nil
    end

    ctx.events.parallel("par")
    value.should eq(3)
  end

  it "handles background execution without blocking" do
    ctx     = Cordis::Context.new
    channel = Channel(Bool).new

    ctx.events.on("bg") do |args|
      channel.send(true)
      nil
    end

    ctx.events.background("bg")
    channel.receive.should be_true
  end

  it "uses custom execution contexts for async events" do
    ctx      = Cordis::Context.new
    exec_ctx = Fiber::ExecutionContext::Concurrent.new("test_exec")
    ctx.execution_context = exec_ctx

    ran_in_context = false

    ctx.events.on("test") do |args|
      ran_in_context = Fiber.current.execution_context == exec_ctx
      nil
    end

    ctx.events.parallel("test")
    ran_in_context.should be_true
  end

  it "handles MessagePack::Any types in event arguments safely" do
    ctx          = Cordis::Context.new
    received_val = ""

    ctx.events.on("msgpack_event") do |args|
      payload      = args[0].as(MessagePack::Any)
      received_val = payload["key"].as_s
      nil
    end

    msgpack_payload = MessagePack.unpack({"key" => "decoded_value"}.to_msgpack)
    ctx.events.emit("msgpack_event", [msgpack_payload.as(Cordis::Any)])

    received_val.should eq("decoded_value")
  end

  it "times out parallel execution if a hook hangs" do
    ctx = Cordis::Context.new

    ctx.events.on("hang_par") do |args|
      sleep 5.seconds
      nil
    end

    expect_raises(Exception, /TimeoutError/) do
      ctx.events.parallel("hang_par", Array(Cordis::Any).new, 10.milliseconds)
    end
  end

  it "times out serial execution if a hook hangs" do
    ctx = Cordis::Context.new

    ctx.events.on("hang_ser") do |args|
      sleep 5.seconds
      nil
    end

    expect_raises(Exception, /TimeoutError/) do
      ctx.events.serial("hang_ser", Array(Cordis::Any).new, 10.milliseconds)
    end
  end
end
