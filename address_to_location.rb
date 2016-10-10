# Script that uses the Google Maps Geocoding API to get the lat long coordinates of addresses,
# then converts them to UTM coordinates.
#
# Script usage:
# ruby address_to_location.rb <api_key> <input_csv_file> <output_csv_file>
# Arguments:
#  1. api_key: Google Maps Geocoding API key
#  2. input_csv_file: expects the path to a csv file with the following format:
#     ADDRESS;COUNTRY[;UTM_ZONE][; semicolon separated list of optional columns]
#     UTM_ZONE, if specified, can be used to force the coordinates into another UTM zone than it belongs to.
#     Optional columns can be whatever you want. They will just be written to the output file as extra info.
#     Example:
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
UTM_ZONE_KEY = "utm_zone"
REQUEST_KEY = "request"

UTM_NORTH = "UTM_NORTH"
UTM_EAST = "UTM_EAST"

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

# close input file
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

# Method for handling the response status
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
         puts "Request #{request} was denied. #{error_string}"
      when 'INVALID_REQUEST'
         puts "Request #{request} is invalid. #{error_string}"
      when 'UNKNOWN_ERROR'
         puts "Unknown error occured for request #{request}. #{error_string}"
   end

   return should_continue
end

# Opens or creates output file for writing
output_file = File.new(OUTPUT_FILE_PATH, 'w')

# writes header
headers_without_utm_zone = headers.reject {|element| element == UTM_ZONE_KEY}
output_file.puts("#{headers_without_utm_zone.join(DELIMITER)}#{DELIMITER}#{UTM_EAST}#{DELIMITER}#{UTM_NORTH}#{DELIMITER}#{UTM_ZONE_KEY}".upcase)

# performs http requests and writes result to file
file_contents.each do |key, value|
   request = value[REQUEST_KEY]
   response = Net::HTTP.get(URI(request))
   json_result = JSON.parse(response)

   status = json_result["status"]
   error_message = json_result["error_message"]
   unless status == 'OK'
      handle_status?(request, status, error_message) ? next : break
   end

   num_results = json_result["results"].length;
   puts "Request #{request} returned #{num_results}. Choosing first result." if num_results > 1

   # gets the relevant info from the results
   latitude = json_result["results"][0]["geometry"]["location"]["lat"]
   longitude = json_result["results"][0]["geometry"]["location"]["lng"]

   # gets the user defined utm zone for the row, if it exists
   forced_zone = value[UTM_ZONE_KEY]
   forced_zone = forced_zone.nil? || forced_zone == '' ? nil : forced_zone.gsub(/"/, '')
   # converts the lat long coordinate to utm, in the specified zone
   utm_coordinate = GeoUtm::LatLon.new(latitude, longitude).to_utm(:zone => forced_zone)

   # constructs the output and writes to file
   out_line = ""
   headers_without_utm_zone.each do |header|
      out_line << "#{value[header]}#{DELIMITER}"
   end

   out_line << "#{utm_coordinate.e}#{DELIMITER}#{utm_coordinate.n}#{DELIMITER}\"#{utm_coordinate.zone}\""
   output_file.puts(out_line)
end

# close output file
output_file.close
