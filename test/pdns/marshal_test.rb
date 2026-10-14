require "test_helper"

# The ComputeStacks controller stores pending edits as Marshal.dump(zone) in
# dns_zones.saved_state. Dumps written by the gem at 21a31b9 must keep loading and
# committing, and dumps written the controller's way (client cleared) must carry no
# credentials.
class MarshalTest < Minitest::Test
  include PdnsTestHelper

  LEGACY_ENDPOINT = "http://legacy-pdns.test:8081/api/v1/servers".freeze
  LEGACY_FIXTURE = File.expand_path("../fixtures/legacy_zone_21a31b9.marshal", __dir__)

  SERVER_RRSETS = [
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
  ].freeze

  def load_legacy
    Marshal.load(File.binread(LEGACY_FIXTURE))
  end

  def add_acme_record(zone, value)
    record = Pdns::Dns::ZoneRecord.new(nil, nil, "example.com.")
    record.name = "_acme.example.com."
    record.type = "TXT"
    record.ttl = "60"
    record.value = value
    zone.records["TXT"] << record
  end

  def rrset(body, name, type)
    body["rrsets"].select { |r| r["name"] == name && r["type"] == type }
  end

  def assert_expected_commit(body)
    acme = rrset(body, "_acme.example.com.", "TXT")
    assert_equal 1, acme.size
    assert_equal 60, acme.first["ttl"]
    assert_equal ["\"token-one\"", "\"token-two\""], acme.first["records"].map { |r| r["content"] }

    a = rrset(body, "www.example.com.", "A").first
    assert_equal [false, true], a["records"].map { |r| r["disabled"] }
    assert_equal 300, a["ttl"]

    assert_equal ["1 ."], rrset(body, "example.com.", "HTTPS").first["records"].map { |r| r["content"] }
    assert_equal SERVER_RRSETS.first["records"].first["content"],
                 rrset(body, "example.com.", "SOA").first["records"].first["content"]
    assert body["rrsets"].all? { |r| r["changetype"] == "REPLACE" }
  end

  def test_legacy_dump_loads_and_commits_with_its_own_client
    zone = load_legacy
    assert_equal "example.com.", zone.id
    assert_equal "4.1.0", zone.instance_variable_get(:@client).api_version
    assert_nil zone.records["A"].last.disabled
    add_acme_record(zone, "token-two")

    stub_request(:get, "#{LEGACY_ENDPOINT}/localhost/zones/example.com.")
      .to_return(status: 200, headers: JSON_HEADERS, body: zone_json("example.com.", SERVER_RRSETS).to_json)
    patch = stub_request(:patch, "#{LEGACY_ENDPOINT}/localhost/zones/example.com.")
      .with(headers: { "X-API-Key" => "legacy-apikey" })
      .to_return(status: 204)

    zone.save
    assert_expected_commit(patch_body(patch))
  end

  def test_legacy_dump_commits_with_a_reattached_client
    zone = load_legacy
    zone.client = build_client
    add_acme_record(zone, "token-two")
    stub_zone_get("example.com.", zone_json("example.com.", SERVER_RRSETS))
    patch = stub_zone_patch("example.com.")

    zone.save
    assert_expected_commit(patch_body(patch))
    assert_not_requested :any, /legacy-pdns\.test/
  end

  def test_controller_style_dump_carries_no_credentials
    zone = load_legacy
    zone.client = nil
    bytes = Marshal.dump(zone)

    %w[legacy-webpass legacy-apikey legacy-pdns.test].each do |secret|
      refute_includes bytes, secret
    end
    refute_includes bytes, "Pdns::Client"
    refute_includes bytes, "Pdns::Auth"

    reloaded = Marshal.load(bytes)
    assert_raises(Pdns::MissingParameter) { reloaded.save }
    assert_not_requested :any, //

    reloaded.client = build_client
    add_acme_record(reloaded, "token-two")
    stub_zone_get("example.com.", zone_json("example.com.", SERVER_RRSETS))
    patch = stub_zone_patch("example.com.")
    reloaded.save
    assert_expected_commit(patch_body(patch))
  end

  def test_new_dumps_use_plain_object_format
    zone = load_legacy
    zone.client = nil
    bytes = Marshal.dump(zone)
    # Type 'U' (marshal_dump) objects cannot be loaded by the gem at 21a31b9.
    [Pdns::Dns::Zone, Pdns::Dns::ZoneRecord, Pdns::Client, Pdns::Auth].each do |klass|
      refute klass.method_defined?(:marshal_dump), "#{klass} must not define marshal_dump"
      refute klass.method_defined?(:_dump), "#{klass} must not define _dump"
    end
    assert_equal "o", bytes.byteslice(2)
  end
end
