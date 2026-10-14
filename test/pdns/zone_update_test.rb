require "test_helper"

class ZoneUpdateTest < Minitest::Test
  include PdnsTestHelper

  ZONE = "ex.com.".freeze
  SOA = "ns1.ex.com. hostmaster.ex.com. 2024010101 10800 3600 604800 3600".freeze

  def rrset(name, type, ttl, *records)
    { "name" => name, "type" => type, "ttl" => ttl,
      "records" => records.map { |r| r.is_a?(Hash) ? r : { "content" => r, "disabled" => false } } }
  end

  def base_rrsets
    [
      rrset(ZONE, "SOA", 3600, SOA),
      rrset(ZONE, "NS", 3600, "ns1.ex.com.", "ns2.ex.com."),
      rrset("www.ex.com.", "A", 300, "192.0.2.1", { "content" => "192.0.2.2", "disabled" => true }),
      rrset(ZONE, "HTTPS", 3600, "1 . alpn=h2"),
      rrset("old.ex.com.", "CNAME", 3600, "www.ex.com.")
    ]
  end

  # Load the zone via find, then let the test edit it; update! re-GETs the same server state.
  def load_zone(rrsets = base_rrsets)
    @client = build_client
    stub_zone_get(ZONE, zone_json(ZONE, rrsets))
    @patch = stub_zone_patch(ZONE)
    Pdns::Dns::Zone.find(@client, ZONE)
  end

  def new_record(name, type, ttl: nil, **fields)
    r = Pdns::Dns::ZoneRecord.new(@client, nil, ZONE)
    r.name = name
    r.type = type
    r.ttl = ttl unless ttl.nil?
    fields.each { |k, v| r.public_send("#{k}=", v) }
    r
  end

  def sent_rrset(body, name, type)
    found = body["rrsets"].select { |r| r["name"] == name && r["type"] == type }
    assert_equal 1, found.size, "expected one rrset for #{name} #{type}, got #{found.size}"
    found.first
  end

  def contents(rrset)
    rrset["records"].map { |r| r["content"] }
  end

  def test_kept_rrsets_replaced_and_verbatim
    zone = load_zone
    zone.update!
    body = patch_body(@patch)

    soa = sent_rrset(body, ZONE, "SOA")
    assert_equal "REPLACE", soa["changetype"]
    assert_equal [SOA], contents(soa)

    https = sent_rrset(body, ZONE, "HTTPS")
    assert_equal "REPLACE", https["changetype"]
    assert_equal ["1 . alpn=h2"], contents(https)

    ns = sent_rrset(body, ZONE, "NS")
    assert_equal ["ns1.ex.com.", "ns2.ex.com."], contents(ns)
    assert_equal 3600, ns["ttl"]

    body["rrsets"].each { |r| refute r.key?("comments"), "#{r['name']} #{r['type']} has comments" }
  end

  def test_server_rrset_without_local_records_deleted
    zone = load_zone
    zone.records["CNAME"].clear
    zone.update!

    cname = sent_rrset(patch_body(@patch), "old.ex.com.", "CNAME")
    assert_equal({ "name" => "old.ex.com.", "type" => "CNAME", "changetype" => "DELETE" }, cname)
  end

  def test_record_order_within_rrset_preserved
    zone = load_zone
    zone.records["A"][0].ip = "192.0.2.9"
    zone.update!

    a = sent_rrset(patch_body(@patch), "www.ex.com.", "A")
    assert_equal ["192.0.2.9", "192.0.2.2"], contents(a)
  end

  def test_two_new_records_same_rrset_sent_once
    zone = load_zone
    zone.records["TXT"] << new_record("_v.ex.com.", "TXT", value: "one")
    zone.records["TXT"] << new_record("_v.ex.com.", "TXT", value: "two")
    zone.update!

    txt = sent_rrset(patch_body(@patch), "_v.ex.com.", "TXT")
    assert_equal "REPLACE", txt["changetype"]
    assert_equal [%q("one"), %q("two")], contents(txt)
    assert_equal 3600, txt["ttl"]
  end

  def test_new_record_defaults_enabled
    zone = load_zone
    zone.records["TXT"] << new_record("_v.ex.com.", "TXT", value: "one")
    zone.update!

    txt = sent_rrset(patch_body(@patch), "_v.ex.com.", "TXT")
    assert_equal [{ "content" => %q("one"), "disabled" => false }], txt["records"]
  end

  def test_server_disabled_record_stays_disabled_after_unrelated_edit
    zone = load_zone
    zone.records["NS"][1].hostname = "ns3.ex.com."
    zone.update!
    body = patch_body(@patch)

    a = sent_rrset(body, "www.ex.com.", "A")
    assert_equal [{ "content" => "192.0.2.1", "disabled" => false },
                  { "content" => "192.0.2.2", "disabled" => true }], a["records"]
    assert_equal ["ns1.ex.com.", "ns3.ex.com."], contents(sent_rrset(body, ZONE, "NS"))
  end

  def test_legacy_record_without_disabled_inherits_server_value
    zone = load_zone
    zone.records["A"].each { |r| r.remove_instance_variable(:@disabled) }
    assert_nil zone.records["A"][1].disabled
    zone.update!

    a = sent_rrset(patch_body(@patch), "www.ex.com.", "A")
    assert_equal [false, true], a["records"].map { |r| r["disabled"] }
  end

  def test_disabled_always_boolean
    zone = load_zone
    zone.records["A"][0].disabled = "yes"
    zone.update!

    patch_body(@patch)["rrsets"].each do |r|
      Array(r["records"]).each { |rec| assert_includes [true, false], rec["disabled"] }
    end
  end

  def test_ttl_edit_on_one_record_wins
    zone = load_zone
    zone.records["NS"][1].ttl = 60
    zone.update!
    assert_equal 60, sent_rrset(patch_body(@patch), ZONE, "NS")["ttl"]
  end

  def test_ttl_string_sent_as_integer
    zone = load_zone
    zone.records["A"][0].ttl = "60"
    zone.update!
    assert_equal 60, sent_rrset(patch_body(@patch), "www.ex.com.", "A")["ttl"]
  end

  def test_ttl_blank_keeps_server_ttl
    zone = load_zone
    zone.records["A"][0].ttl = ""
    zone.records["A"][1].ttl = " "
    zone.update!
    assert_equal 300, sent_rrset(patch_body(@patch), "www.ex.com.", "A")["ttl"]
  end

  def test_ttl_parsed_base_ten
    zone = load_zone
    zone.records["A"][0].ttl = "010"
    zone.update!
    assert_equal 10, sent_rrset(patch_body(@patch), "www.ex.com.", "A")["ttl"]
  end

  def test_ttl_non_decimal_ignored
    zone = load_zone
    zone.records["A"][0].ttl = "0x1f"
    zone.update!
    assert_equal 300, sent_rrset(patch_body(@patch), "www.ex.com.", "A")["ttl"]
  end

  def test_new_rrset_ttl_from_first_record
    zone = load_zone
    zone.records["TXT"] << new_record("_v.ex.com.", "TXT", ttl: "", value: "one")
    zone.records["TXT"] << new_record("_v.ex.com.", "TXT", ttl: "120", value: "two")
    zone.update!
    assert_equal 120, sent_rrset(patch_body(@patch), "_v.ex.com.", "TXT")["ttl"]
  end

  def test_update_without_client_raises_before_request
    zone = load_zone
    zone.client = nil
    error = assert_raises(Pdns::MissingParameter) { zone.update! }
    assert_equal "zone has no client; set Zone#client= after Marshal.load", error.message
    assert_not_requested :patch, server_url("zones/#{ZONE}")
    assert_requested :get, server_url("zones/#{ZONE}"), times: 1 # only the find
  end

  def test_client_reattached_after_marshal_round_trip
    zone = load_zone
    zone.client = nil
    zone = Marshal.load(Marshal.dump(zone))
    zone.client = @client
    zone.update!
    assert_equal ["ns1.ex.com.", "ns2.ex.com."], contents(sent_rrset(patch_body(@patch), ZONE, "NS"))
  end
end
