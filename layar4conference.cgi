#!/usr/bin/env ruby

# This file is part of layar4conference.
#
# layar4conference is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# layar4conference is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with layar4conference.  If not, see <http://www.gnu.org/licenses/>.
#
# Copyright 2013 William Denton

# CONFIGURING
#
# Configuration details are set in the file config.json.
# Make a copy of config.json.example and edit it.

require 'cgi'
require 'json'
require 'rubygems'
require 'nokogiri'
require 'open-uri'

begin
  config = JSON.parse(File.read("config.json"))
rescue Exception => e
  puts e
  exit 1
end

cgi = CGI.new
params = cgi.params

layer = config.find {|l| l["layer"] == params["layer"][0] }

unless layer["layer"]
  # TODO Handle the error that no such layer is configured here
end

#
# Set up a few things for the Layar response.
#
# Error handling.
# Status 0 indicates success. Change to number in range 20-29 if there's a problem.
errorcode = 0
errorstring = "ok"
radius = params["radius"][0].to_i || 1000 # Default to 1000m radius if none provided
hotspots = []

#
# First source: grab points of interest from Google Maps.
#

# The maps we'll use are in the config file.  There can be more than one.

# http://ruby.bastardsbook.com/chapters/html-parsing/
# http://nokogiri.org/tutorials/searching_a_xml_html_document.html

# NEED TO CALCULATE DISTANCES!
# REmember radius passed to Twitter is in km.

layer["google_maps"].each do |map_url|
  begin
    kml = Nokogiri::XML(open(map_url + "&output=kml"))
    kml.xpath("//xmlns:Placemark").each do |p|
      if p.css("Point").size > 0
        # Must be a nicer way to ignore everything that doesn't have a Point element
        latitude, longitude, altitude = p.css("coordinates").text.split(",")
        # Note that Layar will throw away the end of this text if it's too long.
        hotspot = {
          "id" => p.css("coordinates"), # Could keep a counter but this is unique
          "text" => {
            "title" => p.css("name").text,
            "description" => Nokogiri::HTML(p.css("description").text).css("div").text,
            # For the description, which is in HTML, we need to pick out the text of the
            # element from the XML and then parse it as HTML.  I think.  Seems kooky.
            "footnote" => ""
          },
          "anchor" => {
            "geolocation" => {
              "lat" => latitude,
              "lon" => longitude
            }
          },
          "imageURL" => ""
          # "icon" => {
          #  "url" => "", # Add a default icon to see when scanning around?  Any way to grab a picture?
          #  "type" =>  0
          #},
        }
        hotspots << hotspot
      end
    end
  rescue Exception => error
    # TODO Catch errors better
    STDERR.puts "Error: #{error}"
  end
end

#
# Second source: look for any tweets that were made nearby and also use the right hash tags.
#

# Details about the Twitter Search API (simpler than the full API):
# Twitter Search API: https://dev.twitter.com/docs/using-search
#
# Responses: https://dev.twitter.com/docs/platform-objects/tweets
#
# Geolocating of tweets in the response:
# https://dev.twitter.com/docs/platform-objects/tweets#obj-coordinates

# twitter_search_url = "https://search.twitter.com/search.json?q=" + CGI.escape(layer["search]) + "&rpp=100"
twitter_search_url = "https://search.twitter.com/search.json?geocode=43.6,-79.4,5km&rpp=100"

# geocode=-87.67,41.91,1km

open(twitter_search_url) do |f|
  unless f.status[0] == "200"
    STDERR.puts f.status
    # Set up error for Layar
  else
    @twitter = JSON.parse(f.read)
  end
end

# TODO: Wrap this in a loop so we page back through results until we get
# n results?  Or will this be a problem when there's a large cluster of
# geolocated tweets happening with the same hash tag?

@twitter["results"].each do |r|
  # puts r["from_user"]
  if r["geo"]
    # There is a known latitude and longitude. (Otherwise it's null.')
    # By the way, there is only one kind of point, so this will always be true
    # r["geo"]["type"] == "Point"
    latitude, longitude = r["geo"]["coordinates"]
    hotspot = {
      "id" => r["id"],
      "text" => {
        "title" => "@#{r["from_user"]} (#{r["from_user_name"]})",
        "description" => r["text"],
        "footnote" => r["created_at"]
      },
      # TODO Show local time, or how long ago.
      "anchor" => {
        "geolocation" => {
          "lat" => latitude,
          "lon" => longitude
        }
      },
      "imageURL" => r["profile_image_url"],
      "icon" => {
        "url" => r["profile_image_url"],
        "type" =>  0
      },
    }
    hotspots << hotspot
  end
end

#
# Add more sources here.
#

#
# Finish by feeding everything back to Layar as JSON.
#

response = {
  "layer"           => layer["layer"],
  "showMessage"     => layer["showMessage"],
  "refreshDistance" => 300,
  "refreshInterval" => 100,
  "hotspots"        => hotspots,
  "errorCode"       => errorcode,
  "errorString"     => errorstring,
}

# "NOTE that this parameter must be returned if the GetPOIs request
# doesn't contain a requested radius. It cannot be used to overrule a
# value of radius if that was provided in the request. the unit is
# meter."
# -- http://layar.com/documentation/browser/api/getpois-response/#root-radius
if ! params["radius"]
  response["radius"] = radius
end

puts "Content-type: application/json"
puts
puts response.to_json
