require "rubygems"
require "sinatra"
require "omniauth"
require "omniauth-google-oauth2"
require "haml"
require "ez_http"
require "sanitize"

enable :sessions

before do
  @identifier = ENV['id']
  @secret = ENV['secret']
	@host = request.host
  @host << ":4567" if request.host == "localhost"
end

use OmniAuth::Builder do
  provider :google_oauth2, @identifier, @secret, {
              :scope => "https://www.googleapis.com/auth/userinfo.email,https://www.googleapis.com/auth/userinfo.profile,http://www.google.com/reader/api/",
              :access_type => 'offline', 
              :approval_prompt => 'force', 
              :client_options => {
                  :ssl => {
                      :ca_path => "/etc/certificates/"}}}
end

get "/" do
  redirect "/edition/"
end

get "/edition/" do
	refresh_token = params[:refresh_token]
  @n = params[:n]
  access_token = acquire_new_access_token(refresh_token)
  time_since = Time.now.to_i - 604800 #minus a week!
  results = EZHttp.Get("http://www.google.com/reader/api/0/stream/contents/user/-/state/com.google/starred?n=#{@n}&output=json&ot=#{time_since}&client=SundayReading&oauth_token=#{access_token}")
  begin
    @items = JSON.parse(results.body)['items']
  rescue
    halt 400
  end
  @items.each do |item|
    item['title'].gsub!(/\\\"/, "\"")
    if(item['content'])
      item['content']['content'].gsub!(/\\\"/, "\"")
      item['content']['content'] = Sanitize.clean(item['content']['content'], Sanitize::Config::RELAXED)
    else
      item['summary']['content'].gsub!(/\\\"/, "\"")
      item['summary']['content'] = Sanitize.clean(item['summary']['content'], Sanitize::Config::RELAXED)
    end
  end
  haml :index
end

get "/configure/" do
	session[:ret_url] = params[:return_url]
  session[:fail_url] = params[:failure_url]
	redirect '/auth/google_oauth2'
end

get '/auth/:name/callback' do
  @auth = request.env['omniauth.auth']
  @auth.inspect
  print "\n\n#{@auth.credentials}\n\n"
  uri = URI(session[:ret_url])
  if(uri.host == "remote.bergcloud.com")
    redirect "#{session[:ret_url]}?config[access_token]=#{@auth.credentials.refresh_token}"
  end
end

post "/validate_config/" do
  conf = JSON.parse(params[:config])
  content_type :json
  n = conf["n"] or status 400
  if(n == '1' || n == '3' || n == '5')
    status 200
    { :valid => true}.to_json
  else
    status 400 
    { :valid => false, :errors => "Incorrect article number amount."}.to_json
  end
end


get '/auth/failure' do
  redirect session[:fail_url]
end

def acquire_new_access_token(refresh_token)
  results = EZHttp.Post(
      "https://accounts.google.com/o/oauth2/token",
      "client_id=#{@identifier}&client_secret=#{@secret}&refresh_token=#{refresh_token}&grant_type=refresh_token")
  results = JSON.parse(results.body)
  return results['access_token']
end

error 400 do
  '<center><h1>Error 400!</h1> <br />Bad request, no credenitals provided.</center>'
end