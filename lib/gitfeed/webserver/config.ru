require 'bundler'
require 'rack'
require 'pry'

Bundler.require(:default)

require_relative 'application'
require_relative '../api'

run GitFeed::WebServer::Application.new
