#!/usr/local/bin/ruby
require 'time'
require 'json'
RLIB = '../../rlib'
require_relative "#{RLIB}/wikk_conf.rb"
require 'wikk_webbrowser'

# Get Tide Data via NIWA's API
class TideQuery
  attr_reader :response
  attr_reader :time
  attr_reader :today
  attr_reader :tomorrow

  LONG_DAY = 86400 # Seconds in a day

  def initialize(_tomorrow = false)
    @response = { 'values' => [] }
    @time = Time.now.localtime
    @today = @time.strftime('%Y-%m-%d')
    @tomorrow = (@time + LONG_DAY).strftime('%Y-%m-%d')

    @niwa_conf = JSON.parse(File.read(NIWA_API_KEY))
    WIKK::WebBrowser.https_session(host: 'api.niwa.co.nz', verify_cert: false ) do |ws|
      # https://api.niwa.co.nz/tides/data?lat=-36.99&long=174.4869444&numberOfDays=2&startDate=2019-12-26&apikey=xxxxxxxxx
      response = ws.get_page(query: 'tides/data',
                             form_values: {
                               'lat' => '-36.98939250332647',
                               'long' => '174.47079642531136',
                               'numberOfDays' => '2',
                               'startDate' => @time.strftime('%Y-%m-%d'), # Request todays and tomorrows tides
                               'datum' => 'MSL'
                             },
                             extra_headers: { 'x-apikey' => @niwa_conf.api_key }
                            )
      @response = JSON.parse(response)
    end
  end

  # Format time with am/pm.
  def to_am_pm(time:)
    time.strftime('%I:%M %p')
  end

  def results
    today = []
    tomorrow = []

    @response['values'].each do |h|
      time = Time.parse(h['time']).localtime
      if time.strftime('%Y-%m-%d') == @today
        today << [ to_am_pm(time: time), h['value']]
      else
        tomorrow << [ to_am_pm(time: time), h['value']]
      end
    end

    (0..3).each do |row|
      yield today[row], tomorrow[row]
    end
  end
end

def run
  begin
    high_low = TideQuery.new

    # Create a new tides.html file in tmp directory to ensure we don't break the current one.
    File.open("#{TMP_DIR}/tides.html", 'w') do |fd|
      # Html Header + start of body
      fd.print <<~EOF
        <html>
        <head><title>Karekare Tides</title>
          <META HTTP-EQUIV="Pragma" CONTENT="no-cache">
          <META HTTP-EQUIV="Refresh" CONTENT="3600;URL=/weather/tides.html">
          <!-- #{high_low.time.strftime('%Y-%m-%d %H:%M:%S')} -->
        </head>
        <body>
        <h2>Tides for Karekare Beach</h2>
          <table cellpadding=5 border=1>
          <tr style="background:grey">
            <th>#{high_low.today}</th>
            <th>Height</th>
            <th>#{high_low.tomorrow}</th>
            <th>Height</th></tr>
      EOF
      # Table Body, with tide heights
      high_low.results do |today, tomorrow|
        if today.nil?
          fd.print "  <tr>\n    <td>&nbsp;</td><td>&nbsp;</td>\n"
        else
          fd.print "  <tr>\n    <td>#{today[0]}</td><td align=\"right\">#{today[1]}m</td>\n"
        end
        if tomorrow.nil?
          fd.print "    <td>&nbsp;</td><td>&nbsp;</td>\n  </tr>\n"
        else
          fd.print "    <td>#{tomorrow[0]}</td><td align=\"right\">#{tomorrow[1]}m</td>\n  </tr>\n"
        end
      end

      # Rest of html file
      fd.print <<~EOF
          </table>
          <span style="font-size: x-small">
          Data from the <a href=\"http://www.niwa.co.nz/our-services/online-services/tides\" target=\"_blank\"> National Institute of Water & Atmospheric Research</a><br>
          Tide heights are given in metres above and below the mean sea level.
          </span><br>
          </body>
        </html>
      EOF
    end

    # Replace current tides file, with new one.
    File.rename("#{TMP_DIR}/tides.html", "#{WWW_DIR}/weather/tides.html")
  rescue StandardError => e
    puts e
  end
end

run
