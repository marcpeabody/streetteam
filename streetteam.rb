require 'sinatra/base'
require 'open-uri'
require 'nokogiri'
require 'dalli'

class Streetteam < Sinatra::Base
  get '/' do
    """
    Challenge your RunKeeper Street Team to see who burns the most calories this month (#{formatted_month}).
    <br/><br/>
    To keep track, just add your runkeeper id to the end of this URL. Example: <a href='marcpeabody'>http://streetteam.heroku.com/marcpeabody</a>
    <br/><br/>
    (be patient - it will take a while the *first* time you run this with your id)
    <br/><br/>
    <br/><br/>
    <br/><br/>
    <a href='https://github.com/marcpeabody/streetteam' target='github'>source code</a>
    """
  end

  get '/:runner_id' do
    resetters = (params[:reset] || '').split(',')
    report(params[:runner_id], resetters)
  end
end

def formatted_month(time_string=nil)
  if time_string.nil?
    time = Time.new
  elsif time_string.empty?
    return ""
  else
    time = Time.parse(time_string)
  end
  time.strftime("%b %Y")
  # (time_string.nil? ? Time.new : Time.parse(time_string)).strftime("%b %Y") # Jul 2011
end

def key_month
  formatted_month.delete(' ')
end

def noko(url)
  Nokogiri::HTML(open("http://runkeeper.com#{url}"))
end

def report(runner_id, resetters)
  this_month = formatted_month
  begin
    n = noko "/user/#{runner_id}/streetTeam"
  rescue
    return "No runkeeper.com account was found for #{runner_id}"
  end

  teammate_element_areas = n.css('.streetTeammate')
  teammates = teammate_element_areas.collect do |tea|
    name = tea.css('.usernameLink').inner_html.to_s
    name = "Someone" if name.empty?
    { :name           => name,
      :identifier     => (tea.css('a.avatar').first[:href].to_s =~ /\/user\/(.*)\/profile/) && $1,
      :activity_count => tea.css('.monthlyActivities .mainText').inner_html,
      :month_calories => 0}
  end

  teammates.each do |tm|
    ac  = tm[:activity_count]
    user = tm[:identifier]
    reset_user = resetters.include? user
    lazy_person = activity_count_unchanged?(user, key_month, ac)
    cached_cal  = month_calories(user, key_month)
    # puts "#{tm[:name]}... #{user} activity count: #{ac} unchanged? #{lazy_person}"
    if !reset_user && lazy_person && cached_cal
      tm[:month_calories] = cached_cal
    else
      n = noko "/user/#{tm[:identifier]}/activity"
      this_month_accordion_element = n.css('.accordion').find{|ae| formatted_month(ae.css('.mainText').inner_html) == this_month}
      if this_month_accordion_element
        this_month_container_element = this_month_accordion_element.next_element
        activity_elements = this_month_container_element.css('.activityMonth')
        activities = activity_elements.collect do |a|
          act = {:act_type => a.css('.mainText').inner_html,
                 :miles    => a.css('.distance').inner_html}
          @@calories ||= {}
          act[:calories] = calories_for_activity(a[:link], reset_user)
          act
        end
        tm[:month_calories] = activities.inject(0){|tot,a| tot + a[:calories].gsub(/\,|\s/,'').to_i }
      end
      cache_month_calories(user, key_month, tm[:month_calories])
      cache_activity_count(user, key_month, ac)
    end
  end

  rep = ["#{runner_id}'s team has #{teammates.size} members.",
         "Here's how they rank by calories burned this month."]
  teammates.sort{|x,y| y[:month_calories] <=> x[:month_calories] }.each_with_index do |tm,i|
    name_url = "http://runkeeper.com/user/#{tm[:identifier]}"
    rep << "#{i+1}) <a href='#{name_url}' target='runkeeper'>#{tm[:name]}</a> #{tm[:month_calories]}"
  end
  rep.join('<br/>')
end

def calories_for_activity(link, ignore_cache)
  unless ignore_cache
    cal = m.get(link)
    return cal if cal
  end
  cal = get_calories(link)
  eom = secs_to_end_of_month
  m.set(link, cal, eom)
  cal
end

def activity_count_unchanged?(user, month_year, activity_count)
  key = "#{user}/#{month_year}/activity_count"
  cached_ac = m.get(key)
  return true if cached_ac == activity_count
  return false
end

def cache_activity_count(user, month_year, activity_count)
  key = "#{user}/#{month_year}/activity_count"
  m.set(key, activity_count, secs_to_end_of_month)
end

def month_calories(user, month_year)
  m.get("#{user}/#{month_year}/calories")
end

def cache_month_calories(user, month_year, calories)
  m.set("#{user}/#{month_year}/calories", calories)
end

def get_calories(link)
  noko(link).css('#statsCalories .mainText').inner_html
end

def secs_to_end_of_month(now = DateTime::now())
  end_of_month = DateTime.new(now.year, now.month + 1, 1)
  dif = end_of_month - now
  hours, mins, secs, ignore_fractions = Date.send(:day_fraction_to_time, dif)
  hours * 60 * 60 + mins * 60 + secs
end

def m
  @m ||= Dalli::Client.new(ENV['MEMCACHE_SERVERS'], :username => ENV['MEMCACHE_USERNAME'], :password => ENV['MEMCACHE_PASSWORD'])
end
