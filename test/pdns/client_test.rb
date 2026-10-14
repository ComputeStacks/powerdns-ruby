require "test_helper"

class ClientTest < Minitest::Test
  include PdnsTestHelper

  ZONES_URL = "http://ns1.example.com:8081/api/v1/servers/localhost/zones/example.com.".freeze

  def setup
    WebMock.reset!
  end

  def test_endpoint_forms_resolve_to_same_url
    [
      ENDPOINT,
      "#{ENDPOINT}/",
      "#{ENDPOINT}/localhost",
      "#{ENDPOINT}/localhost/"
    ].each do |endpoint|
      WebMock.reset!
      stub = stub_request(:get, ZONES_URL).to_return(status: 200, body: "{}")
      client = new_client(endpoint)
      client.exec!("get", "zones/example.com.")
      assert_requested stub, times: 1
      assert_equal endpoint, client.endpoint, "endpoint must not be mutated"
    end
  end

  def test_path_already_prefixed_is_not_double_prefixed
    stub = stub_request(:get, ZONES_URL).to_return(status: 200, body: "{}")
    new_client.exec!("get", "localhost/zones/example.com.")
    assert_requested stub, times: 1
  end

  def test_bare_server_path_is_not_prefixed
    stub = stub_server_version
    new_client.exec!("get", "localhost")
    assert_requested stub, times: 1
  end

  def test_zone_containing_server_name_is_prefixed
    stub = stub_request(:get, server_url("zones/mylocalhost.com."))
      .to_return(status: 200, body: "{}")
    new_client.exec!("get", "zones/mylocalhost.com.")
    assert_requested stub, times: 1
  end

  def test_verbs_and_bodies
    payload = { "rrsets" => [] }
    get = stub_request(:get, ZONES_URL).to_return(status: 200, body: "{}")
    post = stub_request(:post, server_url("zones"))
      .with(body: payload.to_json).to_return(status: 201, body: "{}")
    patch = stub_request(:patch, ZONES_URL)
      .with(body: payload.to_json).to_return(status: 204)
    delete = stub_request(:delete, ZONES_URL).to_return(status: 204)

    client = new_client
    client.exec!("get", "zones/example.com.")
    client.exec!("post", "zones", payload)
    client.exec!("put", "zones/example.com.", payload)
    client.exec!("delete", "zones/example.com.")

    [get, post, patch, delete].each { |s| assert_requested s, times: 1 }
  end

  def test_sends_api_key_and_basic_auth
    stub = stub_request(:get, ZONES_URL)
      .with(basic_auth: ["admin", "webpass"], headers: { "X-API-Key" => "apikey" })
      .to_return(status: 200, body: "{}")
    new_client.exec!("get", "zones/example.com.")
    assert_requested stub, times: 1
  end

  def test_404_raises_unknown_object
    stub_request(:get, ZONES_URL).to_return(status: 404)
    assert_raises(Pdns::UnknownObject) { new_client.exec!("get", "zones/example.com.") }
  end

  def test_401_raises_authentication_failed
    stub_request(:get, ZONES_URL).to_return(status: 401)
    error = assert_raises(Pdns::AuthenticationFailed) { new_client.exec!("get", "zones/example.com.") }
    assert_equal "Invalid Login Credentials.", error.message
  end

  def test_422_raises_general_error_with_body
    stub_request(:patch, ZONES_URL).to_return(status: 422, body: '{"error":"bad rrset"}')
    error = assert_raises(Pdns::GeneralError) { new_client.exec!("put", "zones/example.com.", { "a" => 1 }) }
    assert_includes error.message, "bad rrset"
  end

  def test_500_raises_general_error
    stub_request(:get, ZONES_URL).to_return(status: 500, body: "boom")
    error = assert_raises(Pdns::GeneralError) { new_client.exec!("get", "zones/example.com.") }
    assert_equal "boom", error.message
  end

  def test_timeout_raises_connection_timeout
    stub_request(:get, ZONES_URL).to_timeout
    error = assert_raises(Pdns::ConnectionTimeout) { new_client.exec!("get", "zones/example.com.") }
    assert_kind_of Pdns::GeneralError, error
    assert_includes error.message, "ns1.example.com"
    refute_secrets error.message
  end

  def test_connection_refused_raises_connection_failed
    stub_request(:get, ZONES_URL).to_raise(Errno::ECONNREFUSED)
    error = assert_raises(Pdns::ConnectionFailed) { new_client.exec!("get", "zones/example.com.") }
    assert_kind_of Pdns::GeneralError, error
    assert_includes error.message, "ns1.example.com"
    assert_includes error.message, "Errno::ECONNREFUSED"
    refute_secrets error.message
  end

  def test_socket_error_raises_connection_failed
    stub_request(:get, ZONES_URL).to_raise(SocketError)
    error = assert_raises(Pdns::ConnectionFailed) { new_client.exec!("get", "zones/example.com.") }
    assert_kind_of Pdns::GeneralError, error
  end

  def test_unknown_verb_raises_invalid_parameter_without_request
    assert_raises(Pdns::InvalidParameter) { new_client.exec!("head", "zones/example.com.") }
    assert_not_requested :any, /.*/
  end

  def test_new_makes_no_request
    new_client
    assert_not_requested :any, /.*/
  end

  def test_version_returns_server_string
    stub_server_version("4.9.1")
    assert_equal "4.9.1", new_client.version
  end

  def test_version_raises_on_401
    stub_request(:get, server_url).to_return(status: 401)
    assert_raises(Pdns::AuthenticationFailed) { new_client.version }
  end

  def test_api_version_memoizes
    stub = stub_server_version("5.0.7")
    client = new_client
    assert_equal "5.0.7", client.api_version
    assert_equal "5.0.7", client.api_version
    assert_requested stub, times: 1
  end

  def test_api_version_preset_makes_no_request
    client = new_client
    client.api_version = "4.8.0"
    assert_equal "4.8.0", client.api_version

    legacy = new_client
    legacy.instance_variable_set(:@api_version, 0)
    assert_equal 0, legacy.api_version
    assert_not_requested :any, /.*/
  end

  def test_connection_errors_are_general_errors
    assert_operator Pdns::ConnectionFailed, :<, Pdns::GeneralError
    assert_operator Pdns::ConnectionTimeout, :<, Pdns::GeneralError
    assert_operator Pdns::GeneralError, :<, RuntimeError
  end

  private

  def new_client(endpoint = ENDPOINT)
    Pdns::Client.new(endpoint, Pdns::Auth.new(0, "admin", "webpass", "apikey"))
  end

  def refute_secrets(message)
    %w[webpass apikey].each { |secret| refute_includes message, secret }
  end
end
