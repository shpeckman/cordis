# spec/lifecycle_node_spec.cr
require "./spec_helper"

describe Cordis::LifecycleNode do
  it "initializes and activates automatically if no dependencies" do
    ctx  = Cordis::Context.new
    node = Cordis::LifecycleNode.new(ctx)

    node.state.should eq(Cordis::LifecycleNode::State::ACTIVE)
  end

  it "handles effects and state changes on disposal" do
    ctx   = Cordis::Context.new
    node  = Cordis::LifecycleNode.new(ctx)
    value = 0

    node.effect { -> { value += 1; nil } }
    node.dispose

    node.state.should eq(Cordis::LifecycleNode::State::DISPOSED)
    value.should eq(1)
  end

  it "returns a wrapper from effect that untracks and executes" do
    ctx   = Cordis::Context.new
    node  = Cordis::LifecycleNode.new(ctx)
    value = 0

    wrapper = node.effect { -> { value += 1; nil } }
    wrapper.call

    value.should eq(1)

    node.dispose
    value.should eq(1)
  end
end
