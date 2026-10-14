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

  def test_new_zone_without_data_has_default_record_buckets
    zone = Pdns::Dns::Zone.new(nil, "x.com.")
    assert_kind_of Hash, zone.records
    assert_equal [], zone.records["NS"]
    assert_nil zone.name

    assert_equal [], Pdns::Dns::Zone.new(nil, nil).records["NS"]
  end

  def test_find_sets_name
    client = build_client
    stub_zone_get("example.com.", zone_json("example.com."))
    zone = Pdns::Dns::Zone.find(client, "example.com.")
    assert_equal "example.com.", zone.name
    assert_equal "example.com.", zone.id
  end

  def test_list_all_zones_sets_name_and_id
    client = build_client
    stub_request(:get, server_url("zones")).to_return(status: 200, headers: JSON_HEADERS,
      body: [{ "id" => "a.com.", "name" => "a.com.", "kind" => "Native", "dnssec" => false }].to_json)
    zones = Pdns::Dns::Zone.list_all_zones(client)
    assert_equal 1, zones.size
    assert_equal "a.com.", zones.first.name
    assert_equal "a.com.", zones.first.id
    assert_equal [], zones.first.records["A"]
    assert_equal "Native", zones.first.features["kind"]
  end

  def test_unknown_type_bucket_created_on_demand
    client = build_client
    stub_zone_get("example.com.", zone_json("example.com.", [
      { "name" => "_s.example.com.", "type" => "SVCB", "ttl" => 300,
        "records" => [{ "content" => "1 . alpn=h3", "disabled" => true }] }
    ]))
    zone = Pdns::Dns::Zone.find(client, "example.com.")
    assert_equal "1 . alpn=h3", zone.records["SVCB"].first.raw_value
    assert_equal true, zone.records["SVCB"].first.disabled
  end

  def test_save_creates_zone_normalizing_trailing_dot
    ["x.com", " x.com. "].each do |input|
      WebMock.reset!
      client = build_client
      post = stub_request(:post, server_url("zones")).to_return(status: 201, headers: JSON_HEADERS, body: "{}")
      get = stub_zone_get("x.com.", zone_json("x.com."))

      zone = Pdns::Dns::Zone.new(client, nil)
      zone.name = input
      found = zone.save

      body = patch_body(post)
      assert_equal({ "name" => "x.com.", "kind" => "Native",
                     "masters" => Pdns.config[:masters], "nameservers" => Pdns.config[:nameservers] }, body)
      assert_requested get
      assert_kind_of Pdns::Dns::Zone, found
      assert_equal "x.com.", found.id
      assert_equal "x.com.", zone.id
      assert_equal "x.com.", zone.name
    end
  end

  def test_io_without_client_raises_missing_parameter
    zone = Pdns::Dns::Zone.new(nil, "x.com.", zone_json("x.com.", [], "dnssec" => true))
    %i[update! create! sec_params].each do |m|
      error = assert_raises(Pdns::MissingParameter, m.to_s) { zone.public_send(m) }
      assert_equal "zone has no client; set Zone#client= after Marshal.load", error.message
    end
    assert_equal false, zone.destroy
    assert_match(/MissingParameter/, zone.errors.last)
    assert_not_requested :any, /.*/
  end

  def test_sec_params_returns_nil_without_dnssec_even_without_client
    assert_nil Pdns::Dns::Zone.new(nil, "x.com.", zone_json("x.com.")).sec_params
  end

  def test_sec_params_tolerates_keys_without_ds
    client = build_client
    stub_zone_get("x.com.", zone_json("x.com.", [], "dnssec" => true))
    stub_request(:get, server_url("zones/x.com./cryptokeys")).to_return(status: 200, headers: JSON_HEADERS, body: [
      { "id" => 1, "type" => "Cryptokey", "keytype" => "ksk", "active" => true, "flags" => 257,
        "ds" => ["12345 13 2 abcdef", "12345 13 4 012345"] },
      { "id" => 2, "type" => "Cryptokey", "keytype" => "zsk", "active" => true, "flags" => 256 }
    ].to_json)

    params = Pdns::Dns::Zone.find(client, "x.com.").sec_params

    assert_equal 2, params.size
    ksk, zsk = params
    assert_equal "12345", ksk["tag"]
    assert_equal "13", ksk["algo"]
    assert_equal %w[sha256 sha384], ksk["keys"].map { |k| k["digest_type_human"] }
    assert_equal [], zsk["keys"]
    assert_nil zsk["tag"]
    assert_nil zsk["algo"]
    assert_equal "zsk", zsk["keytype"]
  end

  def test_sec_params_csk_shape
    client = build_client
    stub_zone_get("x.com.", zone_json("x.com.", [], "dnssec" => true))
    stub_request(:get, server_url("zones/x.com./cryptokeys")).to_return(status: 200, headers: JSON_HEADERS, body: [
      { "id" => 3, "type" => "Cryptokey", "keytype" => "csk", "active" => true, "flags" => 257,
        "ds" => ["111 8 1 aa", "111 8 2 bb", "111 8 3 cc", "111 8 4 dd", "111 8 9 ee"] }
    ].to_json)

    csk = Pdns::Dns::Zone.find(client, "x.com.").sec_params.first

    assert_equal({ "id" => 3, "tag" => "111", "algo" => "8", "active" => true, "flags" => 257,
                   "keytype" => "csk", "type" => "Cryptokey" }, csk.except("keys"))
    assert_equal ["sha1", "sha256", "gost r 34.11-94", "sha384", "unknown"],
                 csk["keys"].map { |k| k["digest_type_human"] }
    assert_equal({ "tag" => "111", "algo" => "8", "digest_type" => "2", "digest_type_human" => "sha256",
                   "digest" => "bb" }, csk["keys"][1])
  end
end
