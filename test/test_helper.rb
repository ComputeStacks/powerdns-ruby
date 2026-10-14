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

  # rrsets: [{ "name" =>, "type" =>, "ttl" =>, "records" => [{ "content" =>, "disabled" => }] }]
  def zone_json(name, rrsets = [], extra = {})
    { "id" => name, "name" => name, "kind" => "Native", "dnssec" => false, "rrsets" => rrsets }.merge(extra)
  end

  def stub_zone_get(name, body)
    stub_request(:get, server_url("zones/#{name}"))
      .to_return(status: 200, headers: JSON_HEADERS, body: body.to_json)
  end

  def stub_zone_patch(name)
    stub_request(:patch, server_url("zones/#{name}")).to_return(status: 204)
  end

  # Parsed JSON body of the last request matching a stub.
  def patch_body(stub)
    request = WebMock::RequestRegistry.instance.requested_signatures.hash.keys
      .select { |sig| stub.request_pattern.matches?(sig) }.last
    refute_nil request, "expected a request matching #{stub.request_pattern}"
    JSON.parse(request.body)
  end
end
