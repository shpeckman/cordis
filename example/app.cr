# example/app.cr
require "../src/cordis"

class DatabaseService < Cordis::Service
  def initialize(ctx : Cordis::Context)
    super(ctx, "database")
  end

  def query(sql : String) : String
    "[{id: 1, name: \"Alice\"}, {id: 2, name: \"Bob\"}]"
  end
end

class WebServer
  include Cordis::Injectable

  def initialize(ctx : Cordis::Context)
    ctx.events.on("server/request") do |args|
      db     = ctx.database.as(DatabaseService)
      result = db.query("SELECT * FROM users")
      ctx.logger.info("Request processed: #{result}")
      nil
    end

    ctx.node.effect do
      ctx.logger.info("WebServer initialized and bound to port 8080")
      -> {
        ctx.logger.info("WebServer connection drained and shut down")
        nil
      }
    end
  end
end

class MetricPlugin
  include Cordis::Injectable

  def initialize(ctx : Cordis::Context)
    ctx.events.on("server/request") do |args|
      ctx.logger.debug("Metrics tracked for incoming request")
      nil
    end
  end
end

app = Cordis::Context.new

app.registry.plugin("database", DatabaseService.new(app))

api_context = app.isolate("api")
api_context.registry.plugin("web_server", WebServer.new(api_context))
api_context.registry.plugin("metrics", MetricPlugin.new(api_context))

app.events.emit("server/request")

app.node.dispose
