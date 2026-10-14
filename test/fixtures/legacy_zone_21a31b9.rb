# Generates legacy_zone_21a31b9.marshal: a Pdns::Dns::Zone as the controller stored it in
# dns_zones.saved_state with the gem at 21a31b9 (client and credentials included, plus one
# controller-appended record). Not run by the suite; kept so the fixture can be reproduced.
# It must be run against lib/ as of 21a31b9, passed in PDNS_LIB (bundler would otherwise put
# this checkout's lib/ first):
#
#   git worktree add /tmp/pdns-21a31b9 21a31b9
#   PDNS_LIB=/tmp/pdns-21a31b9/lib bundle exec ruby test/fixtures/legacy_zone_21a31b9.rb
$LOAD_PATH.unshift(ENV.fetch("PDNS_LIB"))
require "pdns"
require "webmock"
include WebMock::API
WebMock.enable!

endpoint = "http://legacy-pdns.test:8081/api/v1/servers"
json = { "Content-Type" => "application/json" }
stub_request(:get, "#{endpoint}/localhost").to_return(body: { "version" => "4.1.0" }.to_json, headers: json)
stub_request(:get, "#{endpoint}/localhost/zones/example.com.").to_return(headers: json, body: {
  "id" => "example.com.", "name" => "example.com.", "dnssec" => false,
  "rrsets" => [
    { "name" => "example.com.", "type" => "SOA", "ttl" => 3600, "records" => [
      { "content" => "ns1.example.com. hostmaster.example.com. 2024010101 10800 3600 604800 3600", "disabled" => false }] },
    { "name" => "example.com.", "type" => "NS", "ttl" => 3600, "records" => [
      { "content" => "ns1.example.com.", "disabled" => false },
      { "content" => "ns2.example.com.", "disabled" => false }] },
    { "name" => "www.example.com.", "type" => "A", "ttl" => 300, "records" => [
      { "content" => "192.0.2.1", "disabled" => false },
      { "content" => "192.0.2.2", "disabled" => true }] },
    { "name" => "example.com.", "type" => "MX", "ttl" => 3600, "records" => [
      { "content" => "10 mail.example.com.", "disabled" => false }] },
    { "name" => "example.com.", "type" => "TXT", "ttl" => 3600, "records" => [
      { "content" => "\"v=spf1 -all\"", "disabled" => false }] },
    { "name" => "example.com.", "type" => "HTTPS", "ttl" => 3600, "records" => [
      { "content" => "1 .", "disabled" => false }] }
  ]
}.to_json)

client = Pdns::Client.new(endpoint, Pdns::Auth.new(0, "admin", "legacy-webpass", "legacy-apikey"))
zone = Pdns::Dns::Zone.find(client, "example.com.")

# A pending edit, built the way the controller's Dns::ZoneRecord#create! builds one.
record = Pdns::Dns::ZoneRecord.new(client, nil, "example.com.")
record.name = "_acme.example.com."
record.type = "TXT"
record.ttl = "60"
record.value = "token-one"
zone.records["TXT"] << record

File.binwrite(File.expand_path("legacy_zone_21a31b9.marshal", __dir__), Marshal.dump(zone))
