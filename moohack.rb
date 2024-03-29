# encoding: UTF-8
require 'sinatra'
require 'json'
require 'twitter'
require 'yaml'
require 'moo'

enable :sessions

app_config = YAML::load_file('config.yml')['moo']

# configure the moo client object to use my API key/secret
Moo::Client.config do |c|
  c.oauth_key = app_config['key']
  c.oauth_secret = app_config['secret']
end

get '/' do
  haml :index
end

post '/start' do
  # puts request token in the session
  # this is very dumb. It means that your oauth tokens are stored in cookies.
  # Don't do this in a production app, really.
  @client = Moo::Client.new
  @request_token = @client.get_request_token callback: 'http://localhost:9393/callback'

  session[:twitter_handle] = params[:twitter_handle]
  session[:request_token] = @request_token
  redirect @request_token.authorize_url
end

include Moo::Model

get '/callback' do
  @pack = Pack.new do |p|
    p.product_code = 'minicard'
    p.sides = Twitter.user_timeline(session[:twitter_handle], count:100).map do |t|
      Side.new do |s|
        s.template_code = 'minicard_full_text_landscape'
        s.type = 'image'
        s.data << TextData.new do |text_data|
          text_data.link_id = 'back_line_1'
          text_data.text = t.text
        end
      end
    end

    p.sides << Side.new do |s|
      s.template_code = 'minicard_full_text_landscape'
      s.type = 'details'
      s.data << TextData.new do |text_data|
        text_data.link_id = 'back_line_1'
        text_data.text = session[:twitter_handle]
      end
    end

    p.fill_side_nums
  end

  @request_token = session[:request_token]
  session[:access_token] = @request_token.get_access_token
  at = session[:access_token]

  client = Moo::Client.new
  @res = client.create_pack(at, 'minicard', @pack.to_json)
  response = JSON.load(@res.body)

  # forward user on to the cart
  redirect response['dropIns']['finish']
end


get '/styles.css' do
    sass :style
end
