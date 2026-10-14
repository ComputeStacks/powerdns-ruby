require "pdns"
require "minitest/autorun"
require "webmock/minitest"

WebMock.disable_net_connect!

module PdnsTestHelper
  ENDPOINT = "http://ns1.example.com:8081/api/v1/servers".freeze
  JSON_HEADERS = { "Content-Type" => "application/json" }.freeze

  def server_url(path = nil)
    [ENDPOINT, Pdns.config[:server], path].compact.join("/")
  end

  def stub_server_version(version = "5.0.7")
    stub_request(:get, server_url)
      .to_return(status: 200, body: { "version" => version }.to_json, headers: JSON_HEADERS)
  end

  def build_client
    stub_server_version
    Pdns::Client.new(ENDPOINT, Pdns::Auth.new(0, "admin", "webpass", "apikey"))
  end
end
