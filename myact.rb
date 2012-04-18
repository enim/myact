require 'rubygems'
require 'sinatra'
require 'erb'
require 'oauth2'
require 'oauth'
require 'json'
#require 'net/https'
require 'foursquare2'
require 'twitter'

require './configure.rb'

CALLBACK_PATH = '/4sq/callback'


helpers do
  include Rack::Utils
  alias_method :h, :escape_html
end


before do
  if session[:access_token]
    Twitter.configure do |config|
      config.consumer_key = TW_KEY
      config.consumer_secret = TW_SECRET
      config.oauth_token = session[:access_token]
      config.oauth_token_secret = session[:access_token_secret]
    end
    @twitter = Twitter::Client.new
  else
    @twitter = nil
  end
  if session[:sq_token]
    @foursquare = Foursquare2::Client.new(:oauth_token => session[:sq_token])
  else
    @foursquare = nil
  end
end

def base_url
  default_port = (request.scheme == "http") ? 80 : 443
  port = (request.port == default_port) ? "" : ":#{request.port.to_s}"
  "#{request.scheme}://#{request.host}#{port}"
end

def oauth_consumer
  OAuth::Consumer.new(TW_KEY, TW_SECRET, :site => "https://api.twitter.com/")
end

def sq_oauth_client
  OAuth2::Client.new(SQ_ID, SQ_SECRET, 
    :site => "https://foursquare.com/oauth2/", 
    :authorize_url => "/oauth2/authorize",
    :token_url => "/oauth2/access_token",
    :token_method => :get
  )
end


get '/' do
  #erb %{ <a href="/twitter/timeline">twitter</a><br /><a href="/4sq">foursquare</a> }
  erb :index, :locals => {
    :checkins => [],
    :center => {
      :lat => 35.62534940014396,
      :lng => 139.51889991760254
    }
  }
end

get '/twitter' do
  callback_url = "#{base_url}/twitter/callback"
  request_token = oauth_consumer.get_request_token(:oauth_callback => callback_url)
  session[:request_token] = request_token.token
  session[:request_token_secret] = request_token.secret
  redirect request_token.authorize_url
end

get '/4sq' do
  callback_url = "#{base_url}/4sq/callback"
  redirect sq_oauth_client.auth_code.authorize_url(:redirect_uri => callback_url)
end

get '/twitter/callback' do
  request_token = OAuth::RequestToken.new(
    oauth_consumer, session[:request_token], session[:request_token_secret])
  begin
    @access_token = request_token.get_access_token( {}, 
      :oauth_token => params[:oauth_token],
      :oauth_verifier => params[:oauth_verifier] )	
  rescue OAuth::Unauthorized => @exception
    return erb %{ oauth failed: <%=h @exception.message %>}
  end
  session[:access_token] = @access_token.token
  session[:access_token_secret] = @access_token.secret
  erb %{
    oauth success!
    <dl>
      <dt>access token</dt><dd><%=h @access_token.token %></dd>
      <dt>secret</dt><dd><%=h @access_token.secret %></dd>
    </dl>
    <a href="/twitter/timeline">timeline</a>
  }
end

get '/4sq/callback' do
  code = params[:code]
  session[:code] = code
  params = {
    'response_type' => 'token',
    'redirect_uri' => "#{base_url}/4sq/callback"
  }
  token = sq_oauth_client.auth_code.get_token(code, params)
  session[:sq_token] = token.token
  redirect '/4sq/recent'
  
  erb %{
    oauth success!
    <a href="/4sq/recent">recent</a>
  }
end

get '/twitter/timeline' do
  redirect '/twitter' unless @twitter
  erb %{
    <dl>
    <% @twitter.home_timeline.each do |twit| %>
      <dt><%= twit.user.name %></dt>
      <dd><%= twit.text %></dd>
    <% end %>
    </dl>
    <a href="/">TOP</a>
  }
end

get '/4sq/recent' do
  redirect '/4sq' unless @foursquare
  checkins = []
  ci = @foursquare.user_checkins( {:limit => 100} )
  ci[:items].each do |checkin|
    venue = checkin[:venue]
    c = {
      :shout => checkin[:shout],
      :name  => venue[:name],
      :loc   => venue[:location],
    }
    checkins << c
    #p checkins
  end
  center = checkins[0][:loc]
  p center
  erb :index, :locals => {
     :checkins => checkins,
     :center => center
  }
end

