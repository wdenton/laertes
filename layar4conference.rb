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

require 'json'
require 'time'
require 'cgi'
require 'rubygems'
require 'sinatra'
require 'nokogiri'
require 'open-uri'

before do
  # Make this the default
  content_type 'application/json'
end

configure do
  begin
    set(:config) { JSON.parse(File.read("config.json")) }
  rescue Exception => e
    puts e
    exit 1
  end
end

# UIC Fourm: 41.866862,-87.64597

# URL being called looks like this:
#
# /?
# lang=en
# & countryCode=CA
# & userId=6f85012345
# & lon=-79.000000
# & version=6.0
# & radius=1500
# & lat=43.00000
# & layerName=code4lib2013
# & accuracy=100

# Mandatory params passed in:
# userId
# layerName
# version
# lat
# lon
# countryCode
# lang
# action
#
# Optional but important
# radius

get "/" do
  layer = settings.config.find {|l| l["layer"] == params[:layerName] }
  # TODO Handle case of no layer, catch Exceptions
  # TODO Fail with an error if no lat and lon are given

  # Error handling.
  # Status 0 indicates success. Change to number in range 20-29 if there's a problem.
  errorcode = 0
  errorstring = "ok"

  radius = params[:radius].to_f || 1500 # Default to 1500m radius if none provided
  hotspots = []

  #
  # First source: grab points of interest from Google Maps.
  #

  layer["google_maps"].each do |map_url|
    begin
      kml = Nokogiri::XML(open(map_url + "&output=kml"))
      kml.xpath("//xmlns:Placemark").each do |p|
        if p.css("Point").size > 0 # Nicer way to ignore everything that doesn't have a Point element?

          # Some of the points will be out of range, but lets assume there won't be too many,
          # and we'll deal with it below

          # Ignore all points that are too far away
          longitude, latitude, altitude = p.css("coordinates").text.split(",")
          next if distance_between(params[:lat], params[:lon], latitude, longitude) > radius

          # But if it's within range, build the hotspot information for Layar
          hotspot = {
            "id" => p.css("coordinates").text, # Could keep a counter but this is good enough
            "text" => {
              "title" => p.css("name").text,
              "description" => Nokogiri::HTML(p.css("description").text).css("div").text,
              # For the description, which is in HTML, we need to pick out the text of the
              # element from the XML and then parse it as HTML.  I think.  Seems kooky.
              "footnote" => ""
            },
            "anchor" => {
              "geolocation" => {
                "lat" => latitude.to_f,
                "lon" => longitude.to_f
              }
            },
            # "imageURL" => nil,
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

  radius_km = radius / 1000 # Twitter wants the radius in km

  # twitter_search_url = "https://search.twitter.com/search.json?q=" + CGI.escape(layer["search]) + "&rpp=100"
  # twitter_search_url = "https://search.twitter.com/search.json?geocode=43.6,-79.4,5km&rpp=100"
  twitter_search_url = "https://search.twitter.com/search.json?q=" + CGI.escape(layer["search"]) + "&geocode=#{params[:lat]},#{params[:lon]},#{radius_km}km&rpp=100"
  STDERR.puts "Getting #{twitter_search_url}"

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
      # There is a known latitude and longitude. (Otherwise it's null.)
      # By the way, there is only one kind of point, so this will always be true:
      # r["geo"]["type"] == "Point"

      # Same as before: ignore if the point is not within the radius
      latitude, longitude = r["geo"]["coordinates"]
      # No: rely on Twitter to do it, because we're specifying it in the query.
      # next if distance_between(params[:lat], params[:lon], latitude, longitude) > radius

      hotspot = {
        "id" => r["id"],
        "text" => {
          "title" => "@#{r["from_user"]} (#{r["from_user_name"]})",
          "description" => r["text"],
          "footnote" => since(r["created_at"])
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
      # puts hotspot["text"]["title"]
      hotspots << hotspot
    end
  end

  #
  # Add more sources here!
  #

  #
  # Finish by feeding everything back to Layar as JSON.
  #

  # Sort hotspots by distance
  hotspots.sort! {|x, y|
    distance_between(params[:lat], params[:lon], x["anchor"]["geolocation"]["lat"], x["anchor"]["geolocation"]["lon"]) <=>
    distance_between(params[:lat], params[:lon], y["anchor"]["geolocation"]["lat"], y["anchor"]["geolocation"]["lon"])
  }

  if hotspots.length == 0
    errorcode = 21
    errorstring = "No results found.  Try adjusting your search range and any filters."
    # TODO Customize the error message.
  end

  # In theory we should return up to 50 POIs here (hotspots[0..49]),
  # and if there are more the user would have to page through them.
  # But let's just return them all and let Layar deal with it.
  # TODO Add paging through large sets of results.

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

  response.to_json

end

#
# Helper methods
#

def distance_between(latitude1, longitude1, latitude2, longitude2)
  # Calculate the distance between two points on Earth using the
  # Haversine formula, as taken from https://github.com/almartin/Ruby-Haversine

  latitude1 = latitude1.to_f; longitude1 = longitude1.to_f
  latitude2 = latitude2.to_f; longitude2 = longitude2.to_f

  earthRadius = 6371 # km

  def degrees2radians(value)
    unless value.nil? or value == 0
      value = (value/180) * Math::PI
    end
    return value
  end

  deltaLat = degrees2radians(latitude1  - latitude2)
  deltaLon = degrees2radians(longitude1 - longitude2)
  # deltaLat = degrees2radians(deltaLat)
  # deltaLon = degrees2radians(deltaLon)

  # Calculate square of half the chord length between latitude and longitude
  a = Math.sin(deltaLat/2) * Math.sin(deltaLat/2) +
    Math.cos((latitude1/180 * Math::PI)) * Math.cos((latitude2/180 * Math::PI)) * Math.sin(deltaLon/2) * Math.sin(deltaLon/2);
  # Calculate the angular distance in radians
  c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a))
  distance = earthRadius * c * 1000 # meters
  return distance

end

def since(t)
  # Give a time, presumably pretty recent, express how long it was
  # in a nice readable way.
  mm, ss = (Time.now - Time.parse(t)).divmod(60)
  hh, mm = mm.divmod(60)
  dd, hh = hh.divmod(24)
  if dd > 1
    return "#{dd} days ago"
  elsif dd == 1
    return "#{dd} day and #{hh} hours ago"
  elsif hh > 0
    return "#{hh} hours and #{mm} minutes ago"
  else
    return "#{mm} minutes ago"
  end
end
