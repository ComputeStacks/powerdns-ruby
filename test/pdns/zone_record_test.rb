require "test_helper"

class ZoneRecordTest < Minitest::Test
  def record(type, content, extra = {})
    Pdns::Dns::ZoneRecord.new(nil, nil, nil,
      { "name" => "example.com.", "type" => type, "ttl" => 300, "content" => content }.merge(extra))
  end

  def test_a_and_aaaa
    a = record("A", "192.0.2.1")
    assert_equal "192.0.2.1", a.ip
    assert_equal "192.0.2.1", a.raw_value
    assert_equal 300, a.ttl
    assert_equal "example.com.", a.name

    aaaa = record("AAAA", "2001:db8::1")
    assert_equal "2001:db8::1", aaaa.ip
    assert_equal "2001:db8::1", aaaa.raw_value
  end

  def test_cname_and_ns
    cname = record("CNAME", "target.example.com.")
    assert_equal "target.example.com.", cname.hostname
    assert_equal "target.example.com.", cname.raw_value

    ns = record("NS", "ns1.example.com.")
    assert_equal "ns1.example.com.", ns.hostname
    assert_equal "ns1.example.com.", ns.raw_value
  end

  def test_mx
    mx = record("MX", "10 mail.example.com.")
    assert_equal 10, mx.priority
    assert_equal "mail.example.com.", mx.hostname
    assert_equal "10 mail.example.com.", mx.raw_value
  end

  def test_txt_unquoted_gets_quoted
    txt = Pdns::Dns::ZoneRecord.new(nil, nil, "example.com.")
    txt.type = "TXT"
    txt.value = "v=spf1 -all"
    assert_equal %q("v=spf1 -all"), txt.raw_value
  end

  def test_txt_already_quoted_unchanged
    assert_equal %q("v=spf1 -all"), record("TXT", %q("v=spf1 -all")).raw_value
  end

  def test_txt_multi_string_unchanged
    assert_equal %q("a" "b"), record("TXT", %q("a" "b")).raw_value
  end

  def test_soa_verbatim
    soa = "ns1.example.com. hostmaster.example.com. 2024010101 10800 3600 604800 3600"
    assert_equal soa, record("SOA", soa).raw_value
  end

  def test_unknown_and_other_types_verbatim
    { "HTTPS" => "1 . alpn=h2", "SRV" => "10 5 5060 sip.example.com.",
      "CAA" => %q(0 issue "letsencrypt.org") }.each do |type, content|
      assert_equal content, record(type, content).raw_value, type
    end
  end

  def test_disabled_loaded
    assert_equal true, record("A", "192.0.2.1", "disabled" => true).disabled
    assert_equal false, record("A", "192.0.2.1", "disabled" => false).disabled
    assert_nil Pdns::Dns::ZoneRecord.new(nil, nil, nil).disabled
  end
end
