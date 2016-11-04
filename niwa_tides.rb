#!/usr/local/bin/ruby
require 'net/http'
require 'net/https'
require 'uri'
require 'rubygems'
require 'nokogiri'
require 'time'

#NiWA tide table scraper.
class TideQuery
  attr_reader :resultset, :row_names, :index
  LONG_DAY=86400 #Seconds in a day
  
  def initialize(tomorrow=false)
    @resultset = [] #That is 0 rows, 0 columns
    @row_names = []
    @index = {}
    @cookies = nil
    @debug = false
    
    t = Time.now
    t += LONG_DAY if tomorrow
    extract_table(post_page("www.niwa.co.nz", "/node/26820/results",
                              {
                                "location_name"=>"Karekare" , #Karekare Beach, West Auckland
                                "loc"=>"0", #Indicates user specified location
                                "lat"=>"36 59 27 S", 
                                "lon"=>"174 29 13 E",
                                "datum"=>"MSL",
                                "days"=>"1", #Request one days results 
                                "day"=>"#{t.day}",
                                "month"=>"#{t.month}",
                                "year"=>"#{t.year}",
                                "time"=>"12", #Looks to be midnight, not noon.
                                "showResults"=>"data",
                                "submit"=>"Calculate" # new page uses submit , not "submitbutton"=>"Calculate"))
                              }
                          ) 
                   )
  end
  
  private
 
  #send the query to the server and return the response body.   
  def post_page(host, query, form_values=nil)
    url = URI.parse("https://#{host}/#{query}")
    req = Net::HTTP::Post.new(url.path)
    req.set_form_data(form_values, "&") if form_values != nil
    
    http = Net::HTTP.new(host, 443)   #Create the 
    http.use_ssl = (url.scheme == 'https')        #Use https. Doesn't happen automatically!
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE  #ignore that this is not a signed cert.

    http.start do |session|
      response = session.request(req)
      if(response.code.to_i != 200)
        raise "#{response.code} #{response.message}"
      end
      return response.body
    end
  end

  #take an html response with an embedded table and turn the table rows into Array rows.
  #i.e. [ [row1_column1, row1_column2],...]
  def extract_table(s)
    entry = true
    doc = Nokogiri::HTML(s) 
    tables = doc.xpath('//table')
    tables.each do |table|
      rows = table.xpath("tr") 
      rows.each do |tr|
        new_row = []
        cells = tr.xpath("td") 
        cells.each do |cell|  
          new_row << cell.inner_text.strip #Want the cell contents less the format tags, stripping leading and trailing spaces.
        end
        if(entry == true)
          entry = false
          row_names << new_row
          row_names.each_with_index { |v,i| index[v] = i } #Create a hash index of row names to their index
        else
          @resultset << new_row
        end
      end
    end
  end
end

#Format time with am/pm.
def to_am_pm(time_str)
  t = Time.parse(time_str)
  t.strftime("%I:%M %p")
end

begin
  today = TideQuery.new
  date_today = Time.now
  tomorrow = TideQuery.new(true)
  date_tomorrow = date_today + TideQuery::LONG_DAY

  #Create a new tides.html file in tmp directory to ensure we don't break the current one.
  File.open("/services/www/tmp/tides.html", "w") do |fd|
    #Html Header + start of body
    fd.print <<-EOF
<html>
<head><title>Karekare Tides</title>
  <META HTTP-EQUIV="Pragma" CONTENT="no-cache">
  <META HTTP-EQUIV="Refresh" CONTENT="3600;URL=/weather/tides.html">
  <!-- #{date_today.strftime("%Y-%m-%d %H:%M:%S")} -->
</head>
<body>
<h2>Tides for Karekare Beach</h2>
  <table cellpadding=5 border=1>
  <tr style="background:grey">
    <th>#{date_today.strftime("%b %d")}</th>
    <th>Height</th>
    <th>#{date_tomorrow.strftime("%b %d")}</th>
    <th>Height</th></tr>
EOF
    #Table Body, with tide heights
    (0..3).each do |row|
      if(today.resultset[row] != nil)
        fd.print "  <tr>\n    <td>#{to_am_pm(today.resultset[row][1])}</td><td align=\"right\">#{today.resultset[row][2]}m</td>\n" 
      else
        fd.print "  <tr>\n    <td>&nbsp;</td><td>&nbsp;</td>\n"
      end
      if(tomorrow.resultset[row] != nil)
        fd.print "    <td>#{to_am_pm(tomorrow.resultset[row][1])}</td><td align=\"right\">#{tomorrow.resultset[row][2]}m</td>\n  </tr>\n" 
      else
        fd.print "    <td>&nbsp;</td><td>&nbsp;</td>\n  </tr>\n"
      end
    end
    
    #Rest of html file
    fd.print <<-EOF
  </table>
  <span style="font-size: x-small">
  Data from the <a href=\"http://www.niwa.co.nz/our-services/online-services/tides\" target=\"_blank\"> National Institute of Water & Atmospheric Research</a><br>
  Tide heights are given in metres from the mean level of the sea.
  </span><br>
  </body>
</html>
EOF
  end

  #Replace current tides file, with new one.
  File.rename("/services/www/tmp/tides.html", "/services/www/wikarekare/weather/tides.html")
rescue Exception=>error
  puts error
end
