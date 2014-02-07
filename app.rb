#!/usr/bin/env ruby
# encoding: utf-8

require 'nkf'
require "sinatra/json"
set :slim, :pretty => true

ActiveRecord::Base.establish_connection(ENV['DATABASE_URL'] || 'postgres://berlysia@localhost/imas_ml_dojo')

ADMINKEY = 'YuKiHo_iS_My_pRinCesS'

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

get '/dojo.json' do
  json $cache.get('dojos')
end

get '/round' do
  redirect '/'
end

get '/force_reflesh' do
  $cache.set('dojos', Dojo.order('level desc'), 3600)
  redirect '/round'
end

get '/about' do
  slim :about
end

get '/id_check' do
  slim :id_check
end

post '/id_check' do
  dojo = Dojo.where(:userid => params['userid']).first
  redirect "/update?#{URI.encode dojo.serialize}"
end

get '/update' do
  unless params['adminkey'] == ADMINKEY
    403
  else
    @adminkey = params['adminkey']
    @userid = params['userid']
    @username = params['username']
    @unitname = params['unitname']
    @level = params['level']
    @comment = params['comment']

    dispvalue = []
    [@username, @unitname, @comment].each do |str|
      next if str.nil?
      foo = NKF.nkf('-Wwxm0Z0',str)
      foo.gsub(',','').split(/\D/).map{|i| i.to_i}.sort[-1].tap{|i| i ? dispvalue<<i : nil}
      foo.match(/([0-9,]+)(.[0-9]+)?k/i).tap{|s| break ((s[1].gsub(',','').to_i+s[2].to_f)*1000).to_i if s}.tap{|i| i ? dispvalue<<i : nil}
      foo.match(/([0-9,]+)(.[0-9]+)?万/i).tap{|s| break ((s[1].gsub(',','').to_i+s[2].to_f)*10000).to_i if s}.tap{|i| i ? dispvalue<<i : nil}
    end

    @dispvalue = params['dispvalue'] || dispvalue.max || ''

    slim :update
  end
end

post '/update' do
  unless params['adminkey'] == ADMINKEY
    403
  else
    @completed = false
    if params['delete'].nil?
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
    else
      if params.has_key?('userid') && !params['userid'].nil?
        Dojo.where(:userid => params['userid']).first.destroy
        @completed = true
      end
    end
    slim :update
  end
end

get '/update_shortcut' do
  unless params['adminkey'] == ADMINKEY
    403
  else
    @completed = false
    if params['delete'].nil?
      if %w{userid username level}.all?{|key| params.has_key? key}
        dojo = Dojo.where(:userid => params['userid']).first_or_create.tap do |d|
          d.username = params['username'][0..63]
          d.unitname = params['unitname'][0..11] || ""
          d.level = params['level'].to_i
          d.dispvalue = params['dispvalue'].to_i
          d.comment = params['comment'][0..139] || ""
          d.save
        end
        @completed = true
      end
    else
      if params.has_key?('userid') && !params['userid'].nil?
        Dojo.where(:userid => params['userid']).first.destroy
        @completed = true
      end
    end
    slim :update
  end
end

get '/setting' do
  @levelborder, @valueborder, @showcount = %w{levelborder valueborder showcount}.map do |k|
    if request.cookies[k].nil?
      ""
    else
      request.cookies[k].to_i == 0 ? '' : request.cookies[k].to_i
    end
  end

  slim :setting
end

post '/setting' do
  if params.has_key? 'delete'
    %w{levelborder valueborder showcount target}.each do |k|
      response.delete_cookie(k) if request.cookies.has_key?(k)
    end
    @levelborder = nil
    @valueborder = nil
    @showcount = nil
  else
    %w{levelborder valueborder showcount}.each do |k|
      response.set_cookie(k, {:value => params[k].to_i, :max_age => '2592000'}) if params.has_key?(k) && params[k].to_i > 0
    end
    response.set_cookie('target', {:value => params['target'][0], :max_age => '2592000'}) if params.has_key?('target')
    response.set_cookie('sort', {:value => params['sort'][0], :max_age => '2592000'}) if params.has_key?('sort')

    @levelborder, @valueborder, @showcount = %w{levelborder valueborder showcount}.map do |k|
      if params[k].nil? && request.cookies[k].nil?
        ""
      elsif !params[k].nil?
        params[k].to_i == 0 ? '' : params[k].to_i
      else
        request.cookies[k].to_i == 0 ? '' : request.cookies[k].to_i
      end
    end
  end
  slim :setting
end

get '/list' do
  @levelborder, @valueborder, @showcount = %w{levelborder valueborder showcount}.map do |k|
    params[k].to_i > 0 ? params[k].to_i : request.cookies[k].to_i
  end

  @rows = []
  @rows << Hash[[%w{home link username unitname},%w{マイページ リンク ユーザー名 ユニット名}].transpose]
  @rows << Hash[[%w{level dispvalue},%w{レベル 参考発揮値}].transpose]
  @rows << Hash[[%w{comment},%w{コメント}].transpose]

  @target = 'imas_ml_dojo'

  @dojos = $cache.get('dojos')
  @dojos = @dojos.select{|dojo| dojo.dispvalue <= @valueborder} if @valueborder > 0
  @dojos = @dojos.select{|dojo| dojo.level >= @levelborder}


  if @showcount > 0
    @page = params['page'].to_i == 0 ? 1 : params['page'].to_i
    @pagecount = (@dojos.size % @showcount == 0) ? @dojos.size/@showcount : @dojos.size/@showcount + 1

    if @pagecount <= 5
      @from = 1
      @to = @pagecount
    elsif @page <= 3
      @from = 1
      @to = 5
    elsif @page >=  @pagecount - 2
      @from = @pagecount - 4
      @to = @pagecount
    else
      @from = @page - 2
      @to = @page + 2
    end

    @dojos = @dojos[((@page-1)*@showcount)..(@page*@showcount-1)]
  end

  slim :list
end

get '/' do
  @levelborder, @valueborder, @showcount = %w{levelborder valueborder showcount}.map do |k|
    params[k].to_i > 0 ? params[k].to_i : request.cookies[k].to_i
  end
  # if @valueborder > 0
  #   query_params = ["level >= :level and dispvalue <= :dispvalue", {:level => @levelborder, :dispvalue => @valueborder}]
  # else
  #   query_params = ["level >= :level", {:level => @levelborder}]
  # end

  @target = request.cookies.has_key?('target') ? request.cookies['target'] : '_blank'
  @sorttype = request.cookies.has_key?('sort') ? request.cookies['sort'] : 'random'

  # @dojos = Dojo.where(*query_params).order('level desc')
  # @dojos = @dojos.limit(@showcount) unless @showcount == 0
  # @dojos = @dojos.to_a

  @dojos = $cache.get('dojos')
  @dojos = @dojos.select{|dojo| dojo.dispvalue <= @valueborder} if @valueborder > 0
  @dojos = @dojos.select{|dojo| dojo.level >= @levelborder}
  if @sorttype === 'random'
    @dojos.shuffle!
  elsif @sorttype === 'ascend'
    @dojos.reverse!
  end

  @flag = !!params['flag']

  slim :round
end

=begin

・やりたいこと
表示
登録
編集

・ひつようなこと
道場情報の登録→重複検知
道場情報の更新→認証か管理人の手動にしないと荒らしの可能性
自動取得にするならサブアカウントの取得と運用が必要→規約に直撃
表示 is ちょろい

=end
