# src/cordis/service.cr
abstract class Cordis::Service
  include Injectable

  property ctx  : Context
  property name : String

  def initialize(parent_ctx : Context, @name : String)
    @ctx = parent_ctx
    node = LifecycleNode.new(parent_ctx, false, self.inject)
    @ctx = node.ctx
    @ctx.reflect.provide(@name, self)
  end
end
