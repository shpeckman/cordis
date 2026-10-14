# Cordis

Cordis is a Crystal shard for contextual dependency injection, reactive service lifecycles, and event-driven plugin coordination.

It gives you:

- a root `Cordis::Context` for application state
- named services registered through reflection
- declarative dependencies with `inject`
- lifecycle nodes that activate, suspend, fail, and dispose reactively
- scoped service resolution through isolation contexts
- synchronous, background, parallel, serial, and typed events
- interception contexts for configuration such as logger level and event timeouts

## Requirements

- Crystal `>= 1.21.0`
- `msgpack-crystal` `~> 1.3.5`

## Installation

Add Cordis to `shard.yml`.

For a published shard, use its repository coordinates. For a local checkout:

```yaml
dependencies:
  cordis:
    github: shpeckman/cordis
```

Then install dependencies:

```bash
shards install
```

Require the shard:

```crystal
require "cordis"
```

## Quick start

```crystal
require "cordis"

class DatabaseService < Cordis::Service
  def initialize(ctx : Cordis::Context)
    super(ctx, "database")
  end

  def query(sql : String) : String
    "[]"
  end
end

Cordis.define_service("database", DatabaseService)

class UserRepository < Cordis::Service
  inject "database"

  def initialize(ctx : Cordis::Context)
    super(ctx, "user_repository")

    self.ctx.node.effect do
      users = self.ctx.database.query("SELECT * FROM users")
      self.ctx.logger.info("Loaded users: #{users}")

      -> {
        self.ctx.logger.info("UserRepository stopped")
        nil
      }
    end
  end
end

Cordis.define_service("user_repository", UserRepository)

app = Cordis::Context.new

repo = UserRepository.new(app)
sleep 20.milliseconds
puts repo.ctx.node.state

db = DatabaseService.new(app)
sleep 20.milliseconds
puts repo.ctx.node.state

app.node.dispose
```

Registering `UserRepository` before `DatabaseService` is safe. The repository stays `PENDING` until `database` is available and active.

## Core concepts

### Context

`Cordis::Context` is the runtime boundary for an application or plugin tree.

A context exposes:

- `ctx.root`
- `ctx.parent`
- `ctx.node`
- `ctx.events`
- `ctx.reflect`
- `ctx.registry`
- `ctx.logger`
- `ctx.execution_context`
- `ctx.isolate`
- `ctx.intercept`

Create the root context with:

```crystal
app = Cordis::Context.new
```

Create a child context with:

```crystal
child = app.extend_context
```

Child contexts inherit the root, execution context, event bus, registry, and reflection store. They receive their own logger facade so intercepted configuration can be honored per branch.

### Services

A service inherits from `Cordis::Service` and registers itself by name:

```crystal
class CacheService < Cordis::Service
  def initialize(ctx : Cordis::Context)
    super(ctx, "cache")
  end
end
```

Inside a service constructor, use `self.ctx` after `super`. The `ctx` parameter is the parent context; `self.ctx` is the service's own lifecycle context.

### Dependencies

Declare dependencies with `inject`:

```crystal
class Repository < Cordis::Service
  inject "database", "cache"
end
```

The service lifecycle node stays `PENDING` until every dependency resolves to an active service.

Add dependencies later with:

```crystal
node.add_inject(["metrics"])
```

Retry a failed node with:

```crystal
node.retry
```

### Typed service getters

Generate strict getters with:

```crystal
Cordis.define_service("database", DatabaseService)
```

This adds:

```crystal
ctx.database  # DatabaseService
ctx.database? # DatabaseService?
```

The strict getter raises `Cordis::ServiceNotInjectedError` when the service is missing or inactive.

Dynamic access is also available:

```crystal
ctx.service("database")
ctx.service?("database")
ctx.service_active?("database")
ctx.database
```

## Lifecycle

Every service gets a `Cordis::LifecycleNode`.

States:

- `PENDING` — dependencies are not met yet
- `LOADING` — effects are being activated
- `ACTIVE` — dependencies are met and effects are running
- `SUSPENDED` — dependencies were lost and effects were torn down
- `FAILED` — an effect or teardown raised
- `UNLOADING` — disposal or suspension is in progress
- `DISPOSED` — final state

Useful predicates:

```crystal
node.pending?
node.loading?
node.active?
node.suspended?
node.failed?
node.unloading?
node.disposed?
```

Useful introspection:

```crystal
node.inject
node.dependencies_met?
node.effect_count
node.disposable_count
node.last_error
node.dispose_reason
node.last_transition
```

### Effects

Effects run while a node is active and return a teardown proc:

```crystal
node.effect do
  connection = connect

  -> {
    connection.close
    nil
  }
end
```

Named effects are supported for debugging:

```crystal
node.effect("database connection") do
  -> { nil }
end
```

Adding an effect to a disposed or unloading node raises `Cordis::DisposedError`.

If an effect raises, the node moves to `FAILED`, already-started teardowns are run, and `node.last_error` is set. Call `node.retry` after fixing the underlying condition.

### Disposal

Dispose a node with:

```crystal
node.dispose
node.dispose("shutdown requested")
```

Dispose asynchronously with:

```crystal
node.dispose_async
```

Disposal runs effect teardowns and service-provided cleanup tasks, then broadcasts dependency updates so dependents can suspend.

## Reflection and registry

`ReflectService` is the dependency graph. It tracks service implementations and the lifecycle node that provided them.

```crystal
ctx.reflect.get("database")
ctx.reflect.has?("database")
ctx.reflect.active?("database")
ctx.reflect.impl("database")
ctx.reflect.registered_names
ctx.reflect.keys
ctx.reflect.each do |impl|
  puts impl.name
end
```

`RegistryService` is a lightweight plugin registry for named plugin instances.

```crystal
ctx.registry.plugin("metrics", MetricsPlugin.new)
ctx.registry.get("metrics")
ctx.registry.has?("metrics")
ctx.registry.names
ctx.registry.count
ctx.registry.delete("metrics")
```

Use reflection for injectable services. Use the registry for plugin bookkeeping that should not participate in dependency activation.

## Events

Register a hook:

```crystal
dispose = ctx.events.on("user/created") do |args|
  ctx.logger.info(args[0].as(String))
  nil
end

dispose.call
```

Register a one-shot hook:

```crystal
ctx.events.once("boot") do |_args|
  nil
end
```

Inspect listeners:

```crystal
ctx.events.listener_count("boot")
ctx.events.event_names
```

Execution styles:

```crystal
ctx.events.emit("sync")
ctx.events.background("async")
ctx.events.parallel("fan_out")
ctx.events.serial("pipeline")
ctx.events.bail("pipeline")
```

- `emit` runs hooks synchronously.
- `background` runs hooks without blocking.
- `parallel` runs hooks concurrently and raises `Cordis::AggregateHookError` if any hook fails or times out.
- `serial` runs hooks in order and returns the first non-`nil` result.
- `bail` delegates to `serial`.

### Cancellable hooks

Use `on_cancellable` when a hook should observe timeouts or shutdown:

```crystal
ctx.events.on_cancellable("work") do |args, token|
  token.on_cancel do
    cleanup
    nil
  end

  perform_work
  nil
end
```

A timed-out `parallel` or `serial` call cancels its token. Normal hooks keep their existing signature and behavior.

Shut down async event work with:

```crystal
ctx.events.shutdown
```

After shutdown, async event methods raise `Cordis::DisposedError`.

### Typed events

Create a typed event channel:

```crystal
user_created = ctx.events.typed("user/created", String)

user_created.on do |name|
  ctx.logger.info("created #{name}")
end

user_created.emit("alice")
```

The dynamic string-based event API remains available.

## Isolation

Isolation lets different branches resolve the same logical service name differently.

```crystal
api = app.isolate("api")
worker = app.isolate("worker")
```

Isolation keys resolve upward through the context parent chain.

## Interception

Interception stores branch-local configuration:

```crystal
debug = app.intercept("logger", "debug".as(Cordis::Any))
debug.logger.level
```

Supported built-in interception keys:

- `"logger"` — logger level as a `String`, `Hash(String, String)`, or MessagePack payload
- `"events"` — default event timeout as milliseconds using `Int32`/`Int64`, seconds using `Float64`, or a hash with `"timeout_ms"` / `"timeout_s"`

Examples:

```crystal
ctx.intercept("logger", "error".as(Cordis::Any))
ctx.intercept("events", 250.as(Cordis::Any))
ctx.intercept("events", {"timeout_ms" => "250"}.as(Cordis::Any))
```

## Errors

Cordis provides specific exception types:

- `Cordis::ServiceNotFoundError`
- `Cordis::ServiceNotInjectedError`
- `Cordis::DuplicateServiceError`
- `Cordis::ServiceNotProvidedError`
- `Cordis::DependencyTimeoutError`
- `Cordis::HookExecutionError`
- `Cordis::AggregateHookError`
- `Cordis::LifecycleError`
- `Cordis::DisposedError`

`AggregateHookError` exposes the underlying failures through `#errors`.

## Examples

Run the basic example:

```bash
crystal run example/app.cr
```

Run the reactive lifecycle example:

```bash
crystal run example/reactive_app.cr
```

## Development

Install dependencies:

```bash
shards install
```

Run the specs:

```bash
crystal spec
```