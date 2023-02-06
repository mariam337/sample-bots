require 'httparty'

def main
  url = "https://www.nasa.gov/api/2/ubernode/479003"
  response = HTTParty.get(url)
  doc = JSON.parse(response.body)
  result = {}
  result[:title] = doc["_source"]["title"]
  result[:date] =date_conversion(doc["_source"]["promo-date-time"])
  result[:release_id] = key_value(doc["_source"],"release-id")
  result[:article]  = key_value(doc["_source"],"body").to_s
  puts (result)
end

def date_conversion(date)
  date.split("T")[0]
end

def key_value(doc,key)
  key_value = doc.select{|e| e.include? key}
  key_value.values.join
end

main
