# spec/context_spec.cr
require "./spec_helper"

class DynamicService < Cordis::Service
  def execute
    "executed"
  end
end

describe Cordis::Context do
  it "initializes root properties correctly" do
    ctx = Cordis::Context.new

    ctx.root.should eq(ctx)
    ctx.node.state.should eq(Cordis::LifecycleNode::State::ACTIVE)
    ctx.isolate.empty?.should be_true
    ctx.execution_context.should eq(Fiber::ExecutionContext.default)
  end

  it "extends contexts" do
    ctx   = Cordis::Context.new
    child = ctx.extend_context

    child.root.should eq(ctx.root)
    child.should_not eq(ctx)
  end

  it "inherits execution_context on extend" do
    ctx      = Cordis::Context.new
    exec_ctx = Fiber::ExecutionContext::Concurrent.new("test_exec")
    ctx.execution_context = exec_ctx

    child = ctx.extend_context
    child.execution_context.should eq(exec_ctx)
  end

  it "isolates contexts" do
    ctx   = Cordis::Context.new
    child = ctx.isolate("database")

    child.isolate.has_key?("database").should be_true
    ctx.isolate.has_key?("database").should be_false
  end

  it "intercepts contexts" do
    ctx   = Cordis::Context.new
    child = ctx.intercept("logger", "debug".as(Cordis::Any))

    child.intercept["logger"].should eq("debug")
    ctx.intercept.has_key?("logger").should be_false
  end

  it "intercepts contexts with MessagePack::Any payload" do
    ctx = Cordis::Context.new

    msgpack_payload = MessagePack.unpack({"level" => "debug"}.to_msgpack)
    child           = ctx.intercept("logger", msgpack_payload.as(Cordis::Any))

    intercepted = child.intercept["logger"].as(MessagePack::Any)
    intercepted["level"].as_s.should eq("debug")
  end

  it "resolves dynamic properties via method_missing macro" do
    ctx = Cordis::Context.new
    svc = DynamicService.new(ctx, "dynamic_svc")

    resolved = ctx.dynamic_svc.as(DynamicService)
    resolved.execute.should eq("executed")
  end

  it "raises on missing dynamic properties" do
    ctx = Cordis::Context.new

    expect_raises(Exception, "Service not injected: nonexistent_svc") do
      ctx.nonexistent_svc
    end
  end
end
