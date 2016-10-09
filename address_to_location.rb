# Script that uses the Google Maps Geocoding API to get the lat long coordinates of addresses,
# then converts them to UTM coordinates.
#
# Script usage:
# ruby address_to_location.rb <api_key> <input_csv_file> <output_csv_file>
# Arguments:
#  1. api_key: Google Maps Geocoding API key
#  2. input_csv_file: expects the path to a csv file with the following format:
#     ADDRESS;COUNTRY[; semicolon separated list of optional columns]
#     Example
#     ADDRESS;COUNTRY;SOME_IDENTIFIER
#     "some address";"NO";1
#     "another address";"NO";2
#  3. output_csv_file: the path to the output file. Will have the following format:
#     ADDRESS;COUNTRY[; semicolon separated list of optional columns];UTM_EAST;UTM_NORTH;UTM_ZONE
#     Example:
#     ADDRESS;COUNTRY;SOME_IDENTIFIER;UTM_EAST;UTM_NORTH;UTM_ZONE
#     "some address";"NO";1;1234.123;2345.2345;"32V"
#     "another address";"NO";2;2345.123;3456,2345;"32V"

require 'bundler/setup'
require 'net/http'
require 'json'
require 'cgi'
# Loads third party gems with Bundler
Bundler.require(:default)

# Check argments
if ARGV.length < 3
   puts 'Usage: ruby address_to_location.rb <api_key> <input_csv_file> <output_csv_file>'
   exit 1
end

# Stores the arguments in constants
API_KEY = ARGV[0]
INPUT_FILE_PATH = ARGV[1]
OUTPUT_FILE_PATH = ARGV[2]

DELIMITER = ';'
ADDRESS_KEY = "address"
COUNTRY_KEY = "country"
REQUEST_KEY = "request"

UTM_NORTH = "UTM_NORTH"
UTM_EAST = "UTM_EAST"
UTM_ZONE = "UTM_ZONE"

# Check if input file exists
unless File.exist? INPUT_FILE_PATH
   puts "#{INPUT_FILE_PATH} does not exist"
   exit 1
end

# Opens the input file for reading
input_file = File.new(INPUT_FILE_PATH, 'r')

# gets the header columns
header_line = input_file.readline
headers = header_line.split(DELIMITER).map { |header| header.strip.downcase }

file_contents = {}
# reads the rest of the file
input_file.each do |line|
   values = line.split(DELIMITER)
   column_values = {}
   headers.each_with_index do |header, index|
      column_values[header] = values[index].strip
   end

   file_contents[input_file.lineno - 1] = column_values
end

input_file.close

# Creates the requests
base_url = "https://maps.googleapis.com/maps/api/geocode/json"
file_contents.each do |key, value|
   escaped_address = CGI.escape(value[ADDRESS_KEY].gsub(/"/, ''))
   escaped_country = CGI.escape(value[COUNTRY_KEY].gsub(/"/, ''))
   parameters = "#{ADDRESS_KEY}=#{escaped_address}&components=country:#{escaped_country}&key=#{API_KEY}"
   request = "#{base_url}?#{parameters}"
   value[REQUEST_KEY] = request
end

def handle_status?(request, status, error_message)
   should_continue = true

   error_string = "Error: #{error_message.nil? ? 'N/A' : error_message}"
   case status
      when 'ZERO_RESULTS'
         puts "No results for request #{request}."
      when 'OVER_QUERY_LIMIT'
         # over query limit for the day
         puts "Query limit reached. Exiting."
         should_continue = false
      when 'REQUEST_DENIED'
         puts "Request #{request} was denied. Error: #{error_string}"
      when 'INVALID_REQUEST'
         puts "Request #{request} is invalid. Error: #{error_string}"
      when 'UNKNOWN_ERROR'
         puts "Unknown error occured for request #{request}. Error: #{error_string}"
   end

   return should_continue
end

# Opens or creates output file for writing
output_file = File.new(OUTPUT_FILE_PATH, 'w')

# writes header
output_file.puts("#{headers.join(DELIMITER)}#{DELIMITER}#{UTM_EAST}#{DELIMITER}#{UTM_NORTH}#{DELIMITER}#{UTM_ZONE}".upcase)

# performs http requests and writes result to file
file_contents.each_with_index do |(key, value), index|
   # sleeps 1 second every 50 requests, due to usage limit in the Google Maps Geocoding API
   sleep(1) if (index + 1) % 50 == 0

   request = value[REQUEST_KEY]
   response = Net::HTTP.get(URI(request))
   json_result = JSON.parse(response)

   status = json_result["status"]
   error_message = json_result["error_message"]
   unless status == 'OK'
      handle_status?(request, status, error_message) ? next : break
   end

   # gets the relevant info from the results
   latitude = json_result["results"][0]["geometry"]["location"]["lat"]
   longitude = json_result["results"][0]["geometry"]["location"]["lng"]
   utm_coordinate = GeoUtm::LatLon.new(latitude, longitude).to_utm

   out_line = ""
   headers.each do |header|
      out_line << "#{value[header]}#{DELIMITER}"
   end

   out_line << "#{utm_coordinate.e}#{DELIMITER}#{utm_coordinate.n}#{DELIMITER}\"#{utm_coordinate.zone}\""
   output_file.puts(out_line)
end

output_file.close
