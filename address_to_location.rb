# Script usage:
# ruby address_to_location.rb <api_key> <input_csv_file> <output_csv_file>
# Arguments:
#  1. api_key: Google Maps Geocoding API key
#  2. input_csv_file: expects the path to a csv file with the following format:
#     ADDRESS;COUNTRY[; semi colon separated list of optional columns].
#     Example
#     ADDRESS;COUNTRY;SOME_IDENTIFIER
#     "some address";"NO";1
#     "another address";"NO";2
#  3. output_csv_file: the path to the output file. Will have the following format:
#     ADDRESS;COUNTRY;UTM_NORTH;UTM_EAST;UTM_ZONE;[; semi colon separated list of optional columns]
#     Example:
#     ADDRESS;COUNTRY;UTM_NORTH;UTM_EAST;UTM_ZONE;SOME_IDENTIFIER
#     "some address";"NO";1234.123;2345.2345;"32V";1
#     "another address";"NO";2345.123;3456,2345;"32V";2

require 'bundler/setup'
require 'net/http'
require 'json'
require 'cgi'
require 'pp' # TODO: remove
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
      column_values[header] = values[index].strip.gsub(/"/, '')
   end

   file_contents[input_file.lineno - 1] = column_values
end

input_file.close

pp file_contents # TODO: remove

# Creates the requests
base_url = "https://maps.googleapis.com/maps/api/geocode/json"
requests = []
file_contents.each do |key, value|
   parameters = "#{ADDRESS_KEY}=#{CGI.escape(value[ADDRESS_KEY])}&components=country:#{CGI.escape(value[COUNTRY_KEY])}&key=#{API_KEY}"
   requests.push("#{base_url}?#{parameters}")
end

pp requests # TODO: remove

# Opens or creates output file for writing
output_file = File.new(OUTPUT_FILE_PATH, 'w')

requests.each_with_index do |request, index|
   # sleeps 1 second every 50 requests, due to usage limit in the Google Maps Geocoding API
   sleep(1) if (index + 1) % 50 == 0

   response = HTTP.get(URI(request))
   json_result = JSON.parse(response)
end

output_file.close
