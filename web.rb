#!/usr/bin/env ruby

require 'rubygems'
require 'nokogiri'
require 'sinatra'
require 'open-uri'
require 'rss'

LOG_URL = 'https://easy-rpg.org/irc/log/easyrpg/'
MSG_REGEX = /^\[(\d{2}:\d{2})\] <(.*)> (.*)$/
FEED_ITEM_MAX = 20
DIVIDE_THRESHOLD = 10 * 60 # ten minutes

FeedItems = []

def process_msg(msg, stack)
  if stack.empty? or (stack.last[:time] - msg[:time]) < DIVIDE_THRESHOLD
    stack.push msg
    return
  end

  t = stack.first[:time]

  FeedItems << {
    :link => LOG_URL + ('%04d-%02d-%02d.html#%02d:%02d' % [t.year, t.month, t.day, t.hour, t.min]),
    :title => stack.last[:msg],
    :time => t,
    :description => stack.reverse!.map! { |v|
      "#{v[:time]} &lt#{v[:nick]}&gt #{v[:msg]}" }.join('<br />') }
  stack.clear
end

def fetch_log
  FeedItems.clear
  day_log_names = []

  doc = Nokogiri::HTML(open(LOG_URL))
  doc.xpath('//a[contains(@href, ".html")]').each do |n|
    day_log_names << n.attr(:href)
  end

  msg_stack = []
  day_log_names.reverse!
  for name in day_log_names
    day = name.match(/^(\d{4})-(\d{2})-(\d{2}).html$/)
    raise 'not a day log' unless day

    print "fetching #{LOG_URL + name}...\n"
    doc = Nokogiri::HTML(open(LOG_URL + name))
    msgs = doc.css('body').text.split("\r\n").map! { |msg| msg.match MSG_REGEX }
    msgs.compact!
    next if msgs.empty?

    base_time = Time.gm day[1].to_i, day[2].to_i, day[3].to_i
    msgs.reverse!.each do |msg|
      time = msg[1].match(/(\d{2}):(\d{2})/)
      process_msg({ :time => base_time + ((time[1].to_i * 60 + time[2].to_i) * 60),
                    :nick => msg[2], :msg => msg[3] }, msg_stack)
    end
    
    break if FeedItems.length >= FEED_ITEM_MAX
  end
end

fetch_log

Thread.new do
  loop do
    sleep 60 * 10
    fetch_log
  end
end

use Rack::Deflater

mime_type :ico, 'image/x-icon'
mime_type :atom, 'application/atom+xml'

get '/favicon.ico' do
  content_type :ico
  open('https://easy-rpg.org/favicon.ico')
end

get '/' do
  content_type :atom

  RSS::Maker.make('atom') { |maker|
    maker.channel.author = 'EasyRPG Team'
    maker.channel.updated = Time.now.to_s
    maker.channel.link = LOG_URL
    maker.channel.about = "feed generated from #{LOG_URL}"
    maker.channel.title = '#EasyRPG log feed'

    FeedItems.each do |f|
      maker.items.new_item do |item|
        item.link = f[:link]
        item.title = f[:title]
        item.updated = f[:time]
        item.description = f[:description]
      end
    end
  }.to_s
end
