Calorie Competition by Month
=============

My friends wanted to compete to see who could burn the most calories each month.

Unfortunately, RunKeeper reports total calories and calories per activity, but not calories per month.

streetteam generates a ranking of your RunKeeper Street Team members by calories burned in the current month.

It uses Nokogiri to scrape RunKeeper screens, which can take some time if you have a lot of active friends.
To remedy this, we used dalli on memcache to limit the screen scrapes to the activities that had not been scraped yet.

Hosted at: [http://streetteam.heroku.com/](http://streetteam.heroku.com/)
