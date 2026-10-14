require "test_helper"

class ZoneTest < Minitest::Test
  include PdnsTestHelper

  def test_find_groups_records_by_type
    client = build_client
    assert_equal "5.0.7", client.api_version

    stub_request(:get, server_url("zones/example.com."))
      .with(headers: { "X-API-Key" => "apikey" })
      .to_return(status: 200, headers: JSON_HEADERS, body: {
        "id" => "example.com.",
        "name" => "example.com.",
        "dnssec" => false,
        "rrsets" => [
          { "name" => "example.com.", "type" => "A", "ttl" => 300,
            "records" => [{ "content" => "192.0.2.1", "disabled" => false }] },
          { "name" => "example.com.", "type" => "HTTPS", "ttl" => 3600,
            "records" => [{ "content" => "1 .", "disabled" => false }] }
        ]
      }.to_json)

    zone = Pdns::Dns::Zone.find(client, "example.com.")

    assert_equal "192.0.2.1", zone.records["A"].first.ip
    assert_equal 300, zone.records["A"].first.ttl
    assert_equal "1 .", zone.records["HTTPS"].first.raw_value
  end

  def test_find_returns_nil_for_unknown_zone
    client = build_client
    stub_request(:get, server_url("zones/missing.com.")).to_return(status: 404)

    assert_nil Pdns::Dns::Zone.find(client, "missing.com.")
  end
end
