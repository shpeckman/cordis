# spec/reflect_spec.cr
require "./spec_helper"

class MockService < Cordis::Service
end

describe Cordis::ReflectService do
  it "provides and retrieves services" do
    ctx = Cordis::Context.new
    svc = MockService.new(ctx, "mock")

    result = ctx.reflect.get("mock")
    result.should eq(svc)
  end

  it "sets existing services" do
    ctx  = Cordis::Context.new
    svc1 = MockService.new(ctx, "mock")
    svc2 = MockService.new(ctx, "mock_alt")

    ctx.reflect.set("mock", svc2)
    result = ctx.reflect.get("mock")
    result.should eq(svc2)
  end

  it "raises when setting an unprovided property" do
    ctx = Cordis::Context.new
    svc = MockService.new(ctx, "mock")

    expect_raises(Exception, "Cannot set property without provide") do
      ctx.reflect.set("nonexistent", svc)
    end
  end
end
