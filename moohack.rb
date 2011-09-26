# encoding: UTF-8
require 'sinatra'
require 'oauth'
require 'erb'
require 'json'
require 'sqlite3'
require 'nokogiri'
require 'moo'
require 'twitter'
require 'yaml'


enable :sessions

class Client

  def self.oauth_secret=(secret)
    @@oauth_secret = secret
  end

  def self.oauth_key=(key)
    @@oauth_key = key
  end

  def self.config
    yield self if block_given?
  end


  attr_accessor :oauth_consumer, :oauth_key, :oauth_secret
  def initialize(params = nil)
    unless params.nil?
      @oauth_secret = params[:oauth_secret]
      @oauth_key    = params[:oauth_key]
    end

    yield self if block_given?

    ## set key/secret to default if not set
    @oauth_secret ||= @@oauth_secret
    @oauth_key    ||= @@oauth_key

    ## error if the oauth secret and key have not been set by now
    unless @oauth_secret && @oauth_key  
      raise "Moo Client requires OAuth key/secret to be set"
    end

    initialize_oauth_consumer
  end

  # get the initial request token
  #
  # clients can authorize this token and get the subsequent access token
  def get_request_token(callback_or_hash)
    callback = callback_or_hash.is_a?(String) ? callback_or_hash : callback_or_hash[:callback]
    @oauth_consumer.get_request_token(
      oauth_callback: callback
    )
  end

  def create_pack(access_token, product_code, pack_json)
    call_api(access_token, {
      method:   'moo.pack.createPack',
      product:  product_code.to_s,
      pack:     pack_json
    })
  end

  private
    def initialize_oauth_consumer
      @oauth_consumer = OAuth::Consumer.new(
        @oauth_key,
        @oauth_secret,
        {
          site:               "https://secure.moo.com",
          request_token_path: "/oauth/request_token.php",
          access_token_path:  "/oauth/access_token.php",
          authorize_path:     "/oauth/authorize.php" 
        }
      )
    end

    def call_api(access_token, params = {})
      access_token.post(
        '/api/service/',
        params,
        {
          'Content-Type' => 'application/json'
        }
      )
    end
end

app_config = YAML::load_file('config.yml')['moo']

Client.config do |c|
  c.oauth_key = app_config['key']
  c.oauth_secret = app_config['secret']
end



# puts request token in the session
def start_auth
  @client = Client.new
  @request_token = @client.get_request_token callback: 'http://localhost:9393/input'

  session[:request_token] = @request_token
  redirect @request_token.authorize_url
end

def access_token
  @request_token = session[:request_token]
  session[:access_token] = @request_token.get_access_token
end

include Moo::Model

get '/' do
  haml :index
end

get '/start_auth' do
  start_auth
end

get '/styles.css' do
    sass :style
end

get '/input' do
  haml :input
end

post '/pack' do
    @pack = Pack.new do |p|
      p.product_code = 'minicard'
      p.sides = Twitter.user_timeline('alinajaf', count:100).map do |t|
        Side.new do |s|
          s.template_code = 'minicard_full_text_landscape'
          s.type = 'details'
          s.data << TextData.new do |text_data|
            text_data.link_id = 'back_line_1'
            text_data.text = t.text
          end
        end
      end
    end
    #json_obj = JSON.load(pack)
    #fresh_json = JSON.generate(json_obj)

    # try sending it to moo
    access_token
    at = session[:access_token]
    client = Client.new
    @res = client.create_pack(at, 'minicard', @pack.to_json)
    response = JSON.load(@res.body)

    # forward user on to the cart
    redirect response['dropIns']['finish']
end
