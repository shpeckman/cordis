# src/cordis.cr
require "msgpack"
require "./cordis/errors"
require "./cordis/macros"
require "./cordis/utils"
require "./cordis/logger"
require "./cordis/events"
require "./cordis/lifecycle_node"
require "./cordis/reflect"
require "./cordis/registry"
require "./cordis/context"
require "./cordis/service"

module Cordis
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify }}
end
