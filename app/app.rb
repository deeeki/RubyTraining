require 'sinatra/base'
require 'sinatra/activerecord'
require 'sinatra/reloader'
require 'json'
require 'haml'
require 'redcarpet'

# require all models
require_relative 'models/todo'

class Mosscow < Sinatra::Base
  register Sinatra::ActiveRecordExtension

  set :static, true
  set :public_folder, 'public'
  set :views, File.dirname(__FILE__) + '/views'
  set :raise_errors, true
# set :show_exceptions, false # uncomment here when you do NOT want to see a backtrace
  set :database_file, 'config/database.yml'

  configure :development do
    register Sinatra::Reloader
  end

  before do
    ActiveRecord::Base.establish_connection(ENV['RACK_ENV'].to_sym)
    content_type 'text/html'
  end

  module CamelSnakeConverter
    def to_camel
      gsub(/_+([a-z])/){ |matched| matched.tr('_', '').upcase }
      .sub(/^(.)/){ |matched| matched.downcase }
      .sub(/_$/, '')
    end

    def to_snake
      gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
      .gsub(/([a-z\d])([A-Z])/, '\1_\2')
      .tr('-', '_')
      .downcase
    end
  end

  String.send(:include, CamelSnakeConverter)

  helpers do

    def formatter(args, format)
      if format == :camel
        converter = lambda{ |key| key = key.to_camel if key.is_a?(String); key }
      elsif format == :snake
        converter = lambda{ |key| key = key.to_snake if key.is_a?(String); key }
      end

      case args
        when Hash
          args.reduce({}){ |hash, (key, value)| hash.merge(converter.call(key) => formatter(value, format)) }
        when Array
          args.reduce([]){ |array, value| array << formatter(value, format) }
        else
          args
      end
    end

  end

  get '/problems' do
    haml :problems
  end

  get '/404' do
    redirect '404.html'
  end

  get '/500' do
    <<"EOS"
    <html>
      <head>
        <title>500 Internal Server Error</title>
      </head>
      <body>
        <h1>Internal Server Error</h1>
        <img src='images/500.jpg'>
        <p>
        なんかだめでしたすみませんすみません:(；ﾞﾟ'ωﾟ')::(；ﾞﾟ'ωﾟ'):
        </p>
      </body>
    </html>
EOS
  end

  get '/400' do
    halt 400, haml(:bad_request)
  end

  get '/error' do
    begin
      fail
    rescue
      response.status = 500
      content_type :json
      JSON.dump(message: 'unexpected error')
    end
  end

  get '/' do
    content_type 'text/plain'
    'Hello, Moscow!'
  end

  get '/api/todos' do
    todos = Todo.all

    content_type :json
    JSON.dump(formatter(todos.as_json, :camel))
  end

  delete '/api/todos/:id' do
    todo = Todo.where(id: params[:id]).first
    begin
      todo.destroy
    rescue
      response.status = 500
      content_type :json
      return JSON.dump(message: 'unexpected error')
    end
    response.status = 204
    nil
  end

  put '/api/todos/:id' do
    todo = Todo.where(id: params[:id]).first

    begin
      params = formatter(JSON.parse(request.body.read), :snake)
    rescue => e
      p e.backtrace unless ENV['RACK_ENV'] == 'test'
      halt 400, { 'Content-Type' => 'application/json' }, JSON.dump(message: 'set valid JSON for request raw body.')
    end

    todo.is_done = params['is_done']
    todo.task_title = params['task_title']
    if todo.valid?
      todo.save!
      response.status = 200
      content_type :json
      JSON.dump(formatter(todo.as_json, :camel))
    else
      halt 400, { 'Content-Type' => 'application/json' }, JSON.dump(message: todo.errors.messages)
    end
  end

  post '/api/todos' do
    begin
      params = formatter(JSON.parse(request.body.read), :snake)
    rescue => e
      p e.backtrace unless ENV['RACK_ENV'] == 'test'
      halt 400, { 'Content-Type' => 'application/json' }, JSON.dump(message: 'set valid JSON for request raw body.')
    end

    todo = Todo.new(task_title: params['task_title'],
                    is_done: params['is_done'],
                    order: params['order'])
    if todo.valid?
      todo.save!
      response.status = 201
      content_type :json
      JSON.dump(formatter(todo.as_json, :camel))
    else
      halt 400, { 'Content-Type' => 'application/json' }, JSON.dump(message: todo.errors.messages)
    end
  end

  after do
    ActiveRecord::Base.connection.close
  end
end
