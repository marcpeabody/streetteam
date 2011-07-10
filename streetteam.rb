require 'sinatra/base'
require 'open-uri'
require 'nokogiri'

class Streetteam < Sinatra::Base
  get '/' do
    "Add your runkeeper id to the end of the URL. Example: http://streetteam.heroku.com/bigbadrunninglady"
  end

  get '/:runner_id' do
    report(params[:runner_id])
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

def noko(url)
  Nokogiri::HTML(open("http://runkeeper.com#{url}"))
end

def report(runner_id)
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
    puts "#{tm[:name]}... #{tm[:identifier]}"
    n = noko "/user/#{tm[:identifier]}/activity"
    this_month_accordion_element = n.css('.accordion').find{|ae| formatted_month(ae.css('.mainText').inner_html) == this_month}
    if this_month_accordion_element
      this_month_container_element = this_month_accordion_element.next_element
      activity_elements = this_month_container_element.css('.activityMonth')
      activities = activity_elements.collect do |a|
        act = {:act_type => a.css('.mainText').inner_html,
               :miles    => a.css('.distance').inner_html}
        an = noko a[:link]
        act[:calories] = an.css('#statsCalories .mainText').inner_html
        act
      end
      tm[:month_calories] = activities.inject(0){|tot,a| tot + a[:calories].gsub(/\,|\s/,'').to_i }
    end
  end

  rep = ["#{runner_id}'s team has #{teammates.size} members.",
         "Here's how they rank by calories burned this month."]
  teammates.sort{|x,y| y[:month_calories] <=> x[:month_calories] }.each_with_index do |tm,i|
    rep << "#{i+1}) #{tm[:name]} #{tm[:month_calories]}"
  end
  rep.join('<br/>')
end
