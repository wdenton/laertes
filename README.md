Laertes
=======

This provides channels in the augmented reality smartphone application [Layar](http://www.layar.com/) for people together at the same event or conference.  It pulls together points of interest from group-annotated Google Maps and from geolocated and hashtagged tweets on Twitter and displays them in Layar's Geo Vision view.

In other words, if you're at a conference, you can hold up your smartphone and pan around and see where all of the interesting places are and where everyone's been tweeting from in the last little while.

## Requirements

Laertes is written in [Ruby](http://www.ruby-lang.org/en/) using the [Sinatra](http://www.sinatrarb.com/) web application framework.  There is no database---it does everything on the fly by calling APIs.

You will need to have Ruby and [Rubygems](http://rubygems.org/) installed for this to work.

## Installation

Either fork this GitHub repository and download that or download this directly.  Then use [Bundler](http://gembundler.com/) to first make sure all of the necessary requirements are in place and then to run the application safely.  (Note: when installing Bundler you may need to run `sudo gem install bundler`.)

    $ git clone git@github.com:wdenton/laertes.git
    $ cd laertes
    $ gem install bundler
    $ bundle install
    $ bundle exec rackup config.ru

You should see a message like this:

    [2013-01-22 10:49:56] INFO  WEBrick 1.3.1
    [2013-01-22 10:49:56] INFO  ruby 1.9.3 (2012-04-20) [x86_64-linux]
    [2013-01-22 10:49:56] INFO  WEBrick::HTTPServer#start: pid=14347 port=9292

This means that the web service is running on your machine on port 9292.  You can now test it by either hitting it on the command line or in your browser at a URL like this:

    $ curl "http://localhost:9292/?lon=-87.64597&lat=41.866862&version=6.2&radius=2000&layerName=code4lib2013"

It will respond with JSON output as defined in Layar's [GetPOIs Response](https://www.layar.com/documentation/browser/api/getpois-response/).

## Configuration

## Setting up a layer in Layar


