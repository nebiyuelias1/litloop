require "test_helper"

class ChartProbeTest < ActiveSupport::TestCase
  test "override mechanics" do
    client = Object.new
    client.define_singleton_method(:chat) do |**kwargs|
      markers =
        if kwargs.is_a?(Hash) && kwargs[:messages].to_s.include?("chart.png")
          "CHART-WAS-DETECTED"
        else
          "NARRATIVE"
        end + " msgs=#{kwargs[:messages].class}"
    end
    OtariClient.stub(:new, client) do
      c = OtariClient.new
      first = c.chat(model: "m", messages: [ { role: "user", content: "hi" } ])
      second = c.chat(model: "m", messages: [ { role: "user", content: "renders exactly one file named chart.png. Rules:" } ])
      puts "FIRST=#{first.inspect}"
      puts "SECOND=#{second.inspect}"
    end
  end
end
