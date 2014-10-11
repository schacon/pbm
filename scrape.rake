require 'rest_client'
require 'nokogiri'
require 'json'
require 'awesome_print'
require 'geocoder'

namespace :pbm do
  desc "Scrape the Paris By Mouth website"
  task :scrape => :environment do
    places = File.read("places.json") rescue "{}"
    places = JSON.parse(places)

    url = "http://parisbymouth.com/our-guide-to-paris-restaurants"
    page = RestClient.get url
    html_doc = Nokogiri::HTML(page)
    html_doc.css(".entry-content a").each do |link|
      href = link.attr("href").strip rescue ''

      puts href
      next if href[0, 24] != 'http://parisbymouth.com/'
      next if places[href]
      place = process_place(href)
      places[href] = place
      ap place
      File.open("places.json", 'w') { |file| file.write(JSON.pretty_generate(places)) }
    end
  end

  task :geocode => :environment do
    places = JSON.parse(File.read("places.json"))
    places.each do |url, data|
      next if !data
      next if data['coordinates'][0]
      address = data['address'].strip
      address.gsub!(/\(.*?\)/, '')
      address.gsub!(/(\d\d\d\d\d)/, "Paris \\1")
      ap coord = Geocoder.search(address).first.coordinates rescue []
      places[url]['coordinates'] = coord
      places[url]['address_clean'] = address
      ap address
      sleep 0.2
    end
    File.open("places.json", 'w') { |file| file.write(JSON.pretty_generate(places)) }
  end

  task :geojson => :environment do
    geojson = []
    places = JSON.parse(File.read("places.json"))
    places.each do |url, data|
      next if !data
      point = {
        "type" => "Feature",
        "geometry" => {
          "type" => "Point",
          "coordinates" => [
            data['coordinates'][1],
            data['coordinates'][0]
          ]
        },
        "properties" => data
      }
      geojson << point
    end

    json = {
      "type" => "FeatureCollection",
      "features" => geojson
    }

    File.open("geojson.json", 'w') { |file| file.write(JSON.pretty_generate(json)) }
  end
end

def process_place(place_url)
  puts "getting #{place_url}"

  page = RestClient.get place_url
  html_doc = Nokogiri::HTML(page)

  title = html_doc.css("h1.entry-title")[0].inner_html
  sections = html_doc.css(".entry-content p")

  description = sections[0].inner_html

  keys = {
    "Address" => 'address',
    "Nearest transport" => 'transport',
    "Hours" => 'hours',
    "Reservations" => 'reservations',
    "Telephone" => 'phone',
    "Average price for lunch" => 'lunch_price',
    "Average price for dinner" => 'dinner_price',
    "Style of cuisine" => 'style'
  }

  info = {}
  info['title'] = title
  info['description'] = description

  sections.each do |section|
    meta = section.inner_html.split("<br>\n")
    meta.each do |meta_point|
      key, value = meta_point.split(':')
      key = Nokogiri::HTML(key).content
      if (k = keys[key]) && value
        info[k] = value.strip
      end
    end
  end

  info
rescue
  nil
end
