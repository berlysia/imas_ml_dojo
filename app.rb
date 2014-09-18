#!/usr/bin/env ruby
# encoding: utf-8

require 'nkf'
require "sinatra/json"
require 'sinatra/cross_origin'
set :slim, :pretty => true

configure do
  enable :sessions
end

ActiveRecord::Base.establish_connection(ENV['DATABASE_URL'] || 'postgres://berlysia@localhost/imas_ml_dojo')

ADMINKEY = ENV['IMAS_ML_DOJO_UPDATE_KEY']

DEFAULT_VALUE = {
  'LEVEL_BOUND' => 0,
  'VALUE_BOUND' => 1000000,
  'ORDER' => "DESC",
  'EACH_PAGE_LENGTH' => 20,
  'TARGET' => "UNIQUE",
}

class Dojo < ActiveRecord::Base
  def inspect
    "<#{self.userid}, #{self.username}, #{self.unitname}, Lv:#{self.level}, DispValue:#{self.dispvalue}, comment:#{self.comment}>"
  end

  def serialize
    "userid=#{self.userid}&name=#{self.name}&level=#{self.level}&dispvalue=#{self.dispvalue}&comment=#{self.comment}"
  end
end

class Cache
  def initialize
    @threads = {}
    @hash = {}
  end

  def set(key, val, time)
    puts "#{key}: #{val}, #{time}"
    delete(key) if @threads.has_key? key
    @threads[key] = Thread.new do
      loop do
        @hash[key] = val.to_a
        sleep(time)
      end
    end
  end

  def get(key)
    @hash[key]
  end

  def delete(key)
    @threads[key].kill
    @threads.delete key
    @hash.delete key
  end
end

# cache 1 hour
$cache = Cache.new
$cache.set('dojos', Dojo.order('level desc'), 3600)

error 403 do
  'Access forbidden'
end

# -----
# public APIs
# -----

get '/api/all.json' do
  json $cache.get('dojos')
end

# 互換性のため
get '/dojo.json' do
  json $cache.get('dojos')
end

get '/api/getdojos/?' do
  tmp = $cache.get('dojos')
  offset = params[:offset].to_i
  page = params[:page].to_i
  length = (params[:length]||20).to_i

  tmp = tmp.select{|d|
    params[:level_bound].to_i <= d.level && # TODO ソート済みなので先にレベルで切っておく
    d.dispvalue <= (params[:value_bound]||1000000).to_i
  }
  if length == 0
    if params[:page_max]
      json tmp.size
    elsif (params[:order]||"").upcase === "ASC"
      json tmp.reverse
    else
      json tmp
    end
  else
    if params[:page_max]
      json tmp.size/length
    elsif (params[:order]||"").upcase === "ASC"
      json tmp.reverse[(offset+length*page)...(offset+length*(page+1))]
    else
      json tmp[(offset+length*page)...(offset+length*(page+1))]
    end
  end
end

# -----
# secret APIs
# -----

get '/sapi/force_refresh' do
  $cache.set('dojos', Dojo.order('level desc'), 3600)
  redirect '/'
end

get '/sapi/id_check' do
  slim :id_check
end

post '/sapi/id_check' do
  unless params['adminkey'] == ADMINKEY
    403
  else
    dojo = Dojo.where(:userid => params['userid']).first
    session[:dojo] = dojo
    redirect "/sapi/update?adminkey=#{ADMINKEY}"
  end
end

get '/sapi/update' do
  unless params['adminkey'] == ADMINKEY
    403
  else
    dojo = session[:dojo] || params

    @adminkey = dojo['adminkey']
    @userid = dojo['userid']
    @username = dojo['username']
    @unitname = dojo['unitname']
    @level = dojo['level']
    @comment = dojo['comment']

    dispvalue = []
    [@username, @unitname, @comment].each do |str|
      next if str.nil?
      foo = NKF.nkf('-Wwxm0Z0',str)
      foo.gsub(',','').split(/\D/).map{|i| i.to_i}.sort[-1].tap{|i| i ? dispvalue<<i : nil}
      foo.match(/([0-9,]+)(.[0-9]+)?k/i).tap{|s| break ((s[1].gsub(',','').to_i+s[2].to_f)*1000).to_i if s}.tap{|i| i ? dispvalue<<i : nil}
      foo.match(/([0-9,]+)(.[0-9]+)?万/i).tap{|s| break ((s[1].gsub(',','').to_i+s[2].to_f)*10000).to_i if s}.tap{|i| i ? dispvalue<<i : nil}
    end

    @dispvalue = dojo['dispvalue'] || dispvalue.max || ''

    slim :update
  end
end

post '/sapi/update' do
  cross_origin :allow_origin => 'http://imas.gree-apps.net'
  if params['adminkey'] != ADMINKEY
    403
  elsif params['delete'].nil?
    @completed = false
    if %w{userid username level}.all?{|key| params.has_key? key}

      dispvalue = []
      [params['username'][0..63], params['unitname'][0..11], params['comment'][0..139]].each do |str|
        next if str.nil?
        foo = NKF.nkf('-Wwxm0Z0',str)
        foo.gsub(',','').split(/\D/).map{|i| i.to_i}.sort[-1].tap{|i| i ? dispvalue<<i : nil}
        foo.match(/([0-9,]+)(.[0-9]+)?k/i).tap{|s| break ((s[1].gsub(',','').to_i+s[2].to_f)*1000).to_i if s}.tap{|i| i ? dispvalue<<i : nil}
        foo.match(/([0-9,]+)(.[0-9]+)?万/i).tap{|s| break ((s[1].gsub(',','').to_i+s[2].to_f)*10000).to_i if s}.tap{|i| i ? dispvalue<<i : nil}
      end

      dojo = Dojo.where(:userid => params['userid']).first_or_create.tap do |d|
        d.username = params['username'][0..63]
        d.unitname = params['unitname'][0..11] || ""
        d.level = params['level'].to_i
        d.dispvalue = (params['dispvalue'] || dispvalue.max || '').to_i
        d.comment = params['comment'][0..139] || ""
        d.save
      end
      @completed = true
    end
    slim :update
  else
    @completed = false
    if params.has_key?('userid') && !params['userid'].nil?
      Dojo.where(:userid => params['userid']).first.destroy
      @completed = true
    end
    slim :update
  end
end

# -----
# main
# -----

# 互換性のため
get '/round' do
  redirect '/'
end

get '/about' do
  slim :about
end

get '/setting' do
  @level_bound, @value_bound, @each_page_length = %w{level_bound value_bound each_page_length}.map do |k|
    request.cookies.has_key?(k) ? request.cookies[k].to_i : DEFAULT_VALUE[k.upcase]
  end

  slim :setting
end

post '/setting' do
  if params.has_key? 'delete'
    %w{level_bound value_bound each_page_length target}.each do |k|
      response.delete_cookie(k) if request.cookies.has_key?(k)
    end
  else
    %w{level_bound value_bound each_page_length}.each do |k|
      if params.has_key?(k) && 0 <= params[k].to_i
        response.set_cookie(k, {:value => params[k].to_i, :max_age => '2592000'})
      end
    end
    %w{target sort}.each do |k|
      if params.has_key?(k)
        response.set_cookie(k, {:value => params[k][0], :max_age => '2592000'})
      end
    end
  end

  redirect '/setting'
end

get '/list' do
  @level_bound, @value_bound, @each_page_length = %w{level_bound value_bound each_page_length}.map do |k|
    request.cookies.has_key?(k) ? request.cookies[k].to_i : DEFAULT_VALUE[k.upcase]
  end

  if request.cookies.has_key?('sort')
    @order = ['DESC','ASC'].include?(request.cookies['sort'].upcase) ? request.cookies['sort'].upcase : DEFAULT_VALUE['ORDER']
  else
    @order = DEFAULT_VALUE["ORDER"]
  end

  @rows = []
  @rows << Hash[[%w{home link username unitname},%w{マイページ リンク ユーザー名 ユニット名}].transpose]
  @rows << Hash[[%w{level dispvalue},%w{レベル 参考発揮値}].transpose]
  @rows << Hash[[%w{comment},%w{コメント}].transpose]

  @target = 'imas_ml_dojo'

  @page = params['page'].to_i

  slim :list
end

get '/next' do
  if ( !(request.referer.nil?) && request.referer.match(request.base_url) )
    slim :next_guide
  else
    level_bound, value_bound = %w{level_bound value_bound}.map do |k|
      request.cookies.has_key?(k) ? request.cookies[k].to_i : DEFAULT_VALUE[k.upcase]
    end
    position = request.cookies.has_key?("position") ? request.cookies["position"].to_i : -1
    init_position = position
    dojos = $cache.get("dojos")

    loop do
      position += 1
      if position == init_position
        @not_found = true
        break
      end

      if dojos.size <= position
        position = -1
      elsif dojos[position].level < level_bound || value_bound < dojos[position].dispvalue
        position += 1
      else
        break
      end
    end

    response.set_cookie("position", {:value => position, :max_age => '2592000'})

    unless @not_found
      redirect "http://imas.gree-apps.net/app/index.php/mypage/user_profile/id/#{dojos[position].userid}/"
    else
      slim :next_guide
    end
  end
end

get '/' do
  @level_bound, @value_bound, @each_page_length = %w{level_bound value_bound each_page_length}.map do |k|
    request.cookies.has_key?(k) ? request.cookies[k].to_i : DEFAULT_VALUE[k.upcase]
  end

  @target = request.cookies.has_key?('target') ? request.cookies['target'] : '_blank'
  @sorttype = request.cookies.has_key?('sort') ? request.cookies['sort'] : 'desc'

  @dojos = $cache.get('dojos')
  @dojos = @dojos.select{|dojo| dojo.dispvalue <= @value_bound} if @value_bound > 0
  @dojos = @dojos.select{|dojo| dojo.level >= @level_bound}
  if @sorttype === 'asc'
    @dojos.reverse!
  end

  @flag = !!params['flag']

  slim :round
end
